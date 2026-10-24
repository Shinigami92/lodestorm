"""Speech from the voice ComfyUI (TTS Audio Suite custom nodes), driven over its HTTP API.

Usage: python tools/voice/comfy.py <engine> <out.flac> <seed> <voice description> -- <text>   (env: VOICE_COMFYUI_URL)
(voice design; cloning from an anchor clip: clone())

The voice ComfyUI is a separate portable install next to the image one (its own Python packages), started on port
8189. Engines: see ENGINES. Models download on first use; the first take after a model swap takes longer.
Never use the suite's bundled example voices (some imitate real people): voices come from voice design or from
our own anchor clips.
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request

URL = os.environ.get("VOICE_COMFYUI_URL", "http://127.0.0.1:8189")
CRLF = bytes([13, 10])

QWEN_SAMPLING = {"top_k": 50, "top_p": 1.0, "temperature": 0.9, "repetition_penalty": 1.05, "max_new_tokens": 2048}
MOSS_SAMPLING = {"temperature": 1.0, "top_p": 0.95, "top_k": 50, "repetition_penalty": 1.1, "max_new_tokens": 4096}


def qwen(variant: str, language: str) -> dict:
    inputs = {"model_variant": variant, "device": "auto", "voice_preset": "None (Zero-shot / Custom)"}
    # Qwen3-TTS needs the suite's shared runtime (Transformers 4); it fails to load in the main environment
    extra = {"language": language, "instruct": "", "runtime_mode": "⚠️ Shared Runtime"}
    return {"class_type": "Qwen3TTSEngineNode", "inputs": inputs | extra | QWEN_SAMPLING}


def moss(variant: str, language: str) -> dict:
    inputs = {"model_variant": variant, "multi_speaker_mode": "Custom Character Switching", "device": "auto"}
    extra = {"language": language, "duration_tokens": 0, "sampler_preset": "Model default", "chunk_minutes": 0}
    return {"class_type": "MossTTSEngineNode", "inputs": inputs | extra | MOSS_SAMPLING}


# Voice design engines: name -> (engine node factory taking a language, model id recorded with each take)
DESIGNERS = {
    "qwen3": (lambda lang: qwen("Voice Design - 1.7B VoiceDesign", lang), "Qwen3-TTS-12Hz-1.7B-VoiceDesign"),
    "moss": (lambda lang: moss("Voice Design 1.7B", lang), "MOSS-VoiceGenerator-1.7B"),
}


# Cloning engines: name -> (engine node factory taking a language, model id recorded with each take)
CLONERS = {
    "qwen3": (lambda lang: qwen("TTS - Base 1.7B (Voice Clone)", lang), "Qwen3-TTS-12Hz-1.7B-Base"),
    "chatterbox": (
        lambda lang: {
            "class_type": "ChatterBoxOfficial23LangEngineNode",
            "inputs": {
                "model_version": "v3",
                "language": lang,
                "device": "auto",
                "exaggeration": 0.5,
                "temperature": 0.8,
                "cfg_weight": 0.5,
                "repetition_penalty": 1.2,
                "min_p": 0.05,
                "top_p": 1.0,
            },
        },
        "Chatterbox multilingual v3",
    ),
    # A German fine-tune of the original Chatterbox (Apache-2.0 tag; check its training data before shipping)
    "kartoffel": (
        lambda lang: {
            "class_type": "ChatterBoxEngineNode",
            "inputs": {
                "language": "German (havok2)",
                "device": "auto",
                "exaggeration": 0.5,
                "temperature": 0.8,
                "cfg_weight": 0.5,
            },
        },
        "havok2/Kartoffelbox-v0.1_0.65h2",
    ),
}


def post(path: str, data: dict) -> dict:
    req = urllib.request.Request(URL + path, json.dumps(data).encode(), {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            # Some endpoints (/free) answer with an empty body
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(e.read().decode()) from e


def get(path: str) -> bytes:
    # Windows sometimes runs out of socket buffers during long polls (WinError 10055): wait and retry
    for attempt in range(10):
        try:
            with urllib.request.urlopen(URL + path) as r:
                return r.read()
        except urllib.error.URLError:
            if attempt == 9:
                raise
            time.sleep(5)
    return b""


def upload(path: str, name: str) -> str:
    """Copy a local clip into the ComfyUI input folder (for LoadAudio) and return its name there."""
    boundary = b"lodestorm-voice-upload"
    with open(path, "rb") as f:
        data = f.read()
    disposition = f'Content-Disposition: form-data; name="image"; filename="{name}"'.encode()
    body = CRLF.join(
        [
            b"--" + boundary,
            disposition,
            b"Content-Type: application/octet-stream",
            b"",
            data,
            b"--" + boundary,
            b'Content-Disposition: form-data; name="overwrite"',
            b"",
            b"true",
            b"--" + boundary + b"--",
            b"",
        ]
    )
    headers = {"Content-Type": "multipart/form-data; boundary=" + boundary.decode()}
    with urllib.request.urlopen(urllib.request.Request(URL + "/upload/image", body, headers)) as r:
        return json.load(r)["name"]


def run(graph: dict, out: str) -> float:
    """Queue a graph whose node "out" is a SaveAudio, write its audio to out and return the seconds it took."""
    pid = post("/prompt", {"prompt": graph})["prompt_id"]
    t0 = time.time()
    while True:
        hist = json.loads(get(f"/history/{pid}"))
        if pid in hist:
            entry = hist[pid]
            if entry.get("status", {}).get("status_str") == "error":
                raise RuntimeError(json.dumps(entry["status"], indent=1))
            audio = entry["outputs"]["out"]["audio"][0]
            query = urllib.parse.urlencode({k: audio[k] for k in ("filename", "subfolder", "type")})
            with open(out, "wb") as f:
                f.write(get(f"/view?{query}"))
            return time.time() - t0
        time.sleep(1)


def design(engine: str, out: str, seed: int, description: str, text: str, language: str = "English") -> float:
    """Make a new voice from a description, speaking text."""
    node = DESIGNERS[engine][0](language)
    graph = {
        "engine": node,
        "design": {
            "class_type": "UnifiedVoiceDesignerNode",
            "inputs": {
                "TTS_engine": ["engine", 0],
                "reference_text": text,
                "seed": seed,
                "voice_instruction": description,
            },
        },
        "out": {"class_type": "SaveAudio", "inputs": {"audio": ["design", 1], "filename_prefix": "voice/lodestorm"}},
    }
    return run(graph, out)


def clone(
    engine: str, out: str, seed: int, anchor: str, anchor_text: str, text: str, language: str = "English"
) -> float:
    """Speak text in the voice of an anchor clip (already uploaded) whose transcript is anchor_text."""
    graph = {
        "load": {"class_type": "LoadAudio", "inputs": {"audio": anchor}},
        "voice": {
            "class_type": "CharacterVoicesNode",
            "inputs": {
                "voice_name": "none",
                "reference_text": anchor_text,
                "trim_start": 0.0,
                "trim_end": 0.0,
                "customized": False,
                "opt_audio_input": ["load", 0],
            },
        },
        "engine": CLONERS[engine][0](language),
        "tts": {
            "class_type": "UnifiedTTSTextNode",
            "inputs": {
                "TTS_engine": ["engine", 0],
                "text": text,
                "narrator_voice": "none",
                "seed": seed,
                "opt_narrator": ["voice", 0],
                "enable_audio_cache": False,
            },
        },
        "out": {"class_type": "SaveAudio", "inputs": {"audio": ["tts", 0], "filename_prefix": "voice/lodestorm"}},
    }
    return run(graph, out)


def convert(out: str, source: str, target: str, target_text: str) -> float:
    """Voice conversion: keep the speech of source (both already uploaded) and give it target's voice."""
    graph = {
        "source": {"class_type": "LoadAudio", "inputs": {"audio": source}},
        "load": {"class_type": "LoadAudio", "inputs": {"audio": target}},
        "target": {
            "class_type": "CharacterVoicesNode",
            "inputs": {
                "voice_name": "none",
                "reference_text": target_text,
                "trim_start": 0.0,
                "trim_end": 0.0,
                "customized": False,
                "opt_audio_input": ["load", 0],
            },
        },
        "engine": CLONERS["chatterbox"][0]("English"),
        "vc": {
            "class_type": "UnifiedVoiceChangerNode",
            "inputs": {
                "TTS_engine": ["engine", 0],
                "source_audio": ["source", 0],
                "narrator_target": ["target", 0],
                "refinement_passes": 1,
                "max_chunk_duration": 30,
                "chunk_method": "smart",
            },
        },
        "out": {"class_type": "SaveAudio", "inputs": {"audio": ["vc", 0], "filename_prefix": "voice/lodestorm"}},
    }
    return run(graph, out)


if __name__ == "__main__":
    args = sys.argv[1:]
    split = args.index("--")
    engine, out, seed = args[0], args[1], int(args[2])
    print(f"{out} ({design(engine, out, seed, ' '.join(args[3:split]), ' '.join(args[split + 1 :])):.1f}s)")
