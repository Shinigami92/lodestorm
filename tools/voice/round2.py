"""Round 2 of the voice spike: the picked anchors cloned onto the character's other lines, by each cloning engine.

Usage: <VoxCPM python> tools/voice/round2.py <character>=<round>/<file> ...   e.g. brannik=round1b/qwen3_s1.flac
Env: VOICE_ROUND (default round2), VOICE_LANGUAGE (en or de, default en), VOICE_ENGINES (default
qwen3,chatterbox,voxcpm), VOICE_COMFYUI_URL. Runs with the VoxCPM environment's python (it has soundfile).

Each anchor speaks every test line except the anchor's own (characters.py). The lines of one anchor and engine are
joined into one take, local/voice/<round>/<character>/<anchor>_<engine>.flac, so a listener hears whether the voice
holds across lines; the single lines stay in parts/. Existing files are skipped. Rate them with rate.py.
"""

import json
import os
import subprocess
import sys
import tempfile

import comfy
import numpy as np
import soundfile
from characters import ANCHOR_LINE_INDEX, CHARACTERS

import db

ROUND = os.environ.get("VOICE_ROUND", "round2")
LANGUAGE = os.environ.get("VOICE_LANGUAGE", "en")
ENGINES = os.environ.get("VOICE_ENGINES", "qwen3,chatterbox,voxcpm").split(",")
NAMES = {"en": "English", "de": "German"}
SEED = 1
PAUSE = 0.7  # seconds of silence between joined lines
HERE = os.path.dirname(os.path.abspath(__file__))


def lines(character: str) -> list[str]:
    column = 0 if LANGUAGE == "en" else 1
    rows = CHARACTERS[character]["lines"]
    return [row[column] for i, row in enumerate(rows) if i != ANCHOR_LINE_INDEX]


def render_comfy(engine: str, character: str, anchor: str, anchor_id: str, anchor_text: str, parts: str) -> None:
    uploaded = None
    for i, text in enumerate(lines(character)):
        out = os.path.join(parts, f"{anchor_id}_{engine}_{LANGUAGE}{i + 1}.flac")
        if os.path.exists(out):
            continue
        uploaded = uploaded or comfy.upload(anchor, f"lodestorm_{character}_{anchor_id}.flac")
        seconds = comfy.clone(engine, out, SEED, uploaded, anchor_text, text, NAMES[LANGUAGE])
        print(f"{out} ({seconds:.1f}s)", flush=True)


def voxcpm_jobs(character: str, anchor: str, anchor_id: str, anchor_text: str, parts: str) -> list[dict]:
    # Reference plus continuation from the anchor: the closest VoxCPM2 gets to the anchor's voice
    return [
        {
            "out": os.path.join(parts, f"{anchor_id}_voxcpm_{LANGUAGE}{i + 1}.flac"),
            "seed": SEED,
            "text": text,
            "reference": anchor,
            "prompt_wav": anchor,
            "prompt_text": anchor_text,
        }
        for i, text in enumerate(lines(character))
    ]


def join(files: list[str], out: str) -> None:
    clips, rate = [], 0
    for f in files:
        audio, rate = soundfile.read(f, dtype="float32")
        clips += [audio, np.zeros(int(PAUSE * rate), dtype="float32")]
    soundfile.write(out, np.concatenate(clips[:-1]), rate)


def main(picks: list[str]) -> None:
    con = db.connect()
    anchors = []
    for pick in picks:
        character, path = pick.split("=")
        anchor_round, file = path.split("/")
        take = con.execute(
            "select * from takes where round = ? and character = ? and file = ?", (anchor_round, character, file)
        ).fetchone()
        anchor_id = f"{anchor_round}-{file.removesuffix('.flac')}"
        folder = db.ROOT / ROUND / character
        os.makedirs(folder / "parts", exist_ok=True)
        anchor = str(db.ROOT / anchor_round / character / file)
        anchors.append((character, anchor, anchor_id, take, str(folder)))

    for engine in ENGINES:
        if engine == "voxcpm":
            # VoxCPM2 needs the VRAM the ComfyUI models hold
            comfy.post("/free", {"unload_models": True, "free_memory": True})
            jobs = [
                job
                for character, anchor, anchor_id, take, folder in anchors
                for job in voxcpm_jobs(character, anchor, anchor_id, take["text"], os.path.join(folder, "parts"))
            ]
            with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
                json.dump(jobs, f)
            subprocess.run([sys.executable, os.path.join(HERE, "voxcpm_run.py"), f.name], check=True)
            os.unlink(f.name)
        else:
            for character, anchor, anchor_id, take, folder in anchors:
                render_comfy(engine, character, anchor, anchor_id, take["text"], os.path.join(folder, "parts"))

        for character, anchor, anchor_id, take, folder in anchors:
            file = f"{anchor_id}_{engine}_{LANGUAGE}.flac"
            out = os.path.join(folder, file)
            if os.path.exists(out):
                continue
            count = len(lines(character))
            join(
                [os.path.join(folder, "parts", f"{anchor_id}_{engine}_{LANGUAGE}{i + 1}.flac") for i in range(count)],
                out,
            )
            model = "openbmb/VoxCPM2" if engine == "voxcpm" else comfy.CLONERS[engine][1]
            con.execute(
                "insert or replace into takes values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    ROUND,
                    character,
                    file,
                    engine,
                    model,
                    SEED,
                    LANGUAGE,
                    take["description"],
                    " / ".join(lines(character)),
                    f"{take['round']}/{take['file']}",
                    0.0,
                    db.now(),
                ),
            )
            con.commit()
            print(f"{ROUND}/{character}/{file}", flush=True)


if __name__ == "__main__":
    main(sys.argv[1:])
