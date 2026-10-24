"""Round 1 of the voice spike: voice-design takes per character, to pick each character's anchor by ear.

Usage: python tools/voice/round1.py [engine ...]   (engines: qwen3, moss, voxcpm; default all)
Env: VOICE_ROUND (default round1; a new name for each change of the descriptions), VOICE_SEEDS (default 1,2,3,4),
VOICE_LANGUAGE (en or de: which text the takes speak; default en), VOICE_CHARACTERS (default all),
VOXCPM_PYTHON (the VoxCPM environment's python), VOICE_COMFYUI_URL.

Every engine renders each character's anchor line (characters.py) from the character's description with SEEDS.
Takes go to local/voice/<round>/<character>/<engine>_s<seed>.flac (existing ones are skipped) and into the voice
database; rate them with rate.py.
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile

import comfy
from characters import ANCHOR_LINE_INDEX, CHARACTERS

import db

ROUND = os.environ.get("VOICE_ROUND", "round1")
LANGUAGE = os.environ.get("VOICE_LANGUAGE", "en")
ONLY = [c for c in os.environ.get("VOICE_CHARACTERS", "").split(",") if c]
NAMES = {"en": "English", "de": "German"}
SEEDS = [int(s) for s in os.environ.get("VOICE_SEEDS", "1,2,3,4").split(",")]
HERE = pathlib.Path(__file__).parent
VOXCPM_PYTHON = os.environ.get(
    "VOXCPM_PYTHON", "D:/shinigami/OpenSource/ComfyUI/ComfyUI_voice/venv-voxcpm/Scripts/python.exe"
)


# German takes are named <engine>_s<seed>_de.flac
SUFFIX = "" if LANGUAGE == "en" else f"_{LANGUAGE}"


def cast():
    """The characters to render, each with its description and anchor line in LANGUAGE."""
    column = 0 if LANGUAGE == "en" else 1
    for key, c in CHARACTERS.items():
        if ONLY and key not in ONLY:
            continue
        description = c["description"]
        if LANGUAGE == "de":
            # A German take needs a German speaker, or voice design adds an English accent
            description = description.replace("Native English speaker", "Native German speaker")
        yield key, description, c["lines"][ANCHOR_LINE_INDEX][column]


def record(
    con, character: str, file: str, engine: str, model: str, seed: int, description: str, text: str, seconds: float
) -> None:
    con.execute(
        "insert or replace into takes values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (ROUND, character, file, engine, model, seed, LANGUAGE, description, text, "design", seconds, db.now()),
    )
    con.commit()
    print(f"{ROUND}/{character}/{file} ({seconds:.1f}s)", flush=True)


def comfy_takes(con, engine: str) -> None:
    model = comfy.DESIGNERS[engine][1]
    for key, description, text in cast():
        for seed in SEEDS:
            file = f"{engine}_s{seed}{SUFFIX}.flac"
            out = db.ROOT / ROUND / key / file
            if out.exists():
                continue
            out.parent.mkdir(parents=True, exist_ok=True)
            seconds = comfy.design(engine, str(out), seed, description, text, NAMES[LANGUAGE])
            record(con, key, file, engine, model, seed, description, text, seconds)


def voxcpm_takes(con) -> None:
    jobs, meta = [], {}
    for key, description, text in cast():
        for seed in SEEDS:
            out = db.ROOT / ROUND / key / f"voxcpm_s{seed}{SUFFIX}.flac"
            if not out.exists():
                jobs.append({"out": str(out), "seed": seed, "text": f"({description}){text}"})
                meta[str(out)] = (key, out.name, seed, description, text)
    if not jobs:
        return
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump(jobs, f)
    proc = subprocess.Popen(
        [VOXCPM_PYTHON, str(HERE / "voxcpm_run.py"), f.name],
        stdout=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        env=os.environ | {"PYTHONUTF8": "1"},
    )
    for line in proc.stdout:
        out, _, rest = line.strip().rpartition(" (")
        if out in meta:
            key, file, seed, description, text = meta[out]
            record(con, key, file, "voxcpm", "openbmb/VoxCPM2", seed, description, text, float(rest.rstrip("s)")))
    if proc.wait():
        raise RuntimeError(f"VoxCPM exited with {proc.returncode}")
    os.unlink(f.name)


if __name__ == "__main__":
    con = db.connect()
    for engine in sys.argv[1:] or ["voxcpm", "moss", "qwen3"]:
        if engine == "voxcpm":
            voxcpm_takes(con)
        else:
            comfy_takes(con, engine)
