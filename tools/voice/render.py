"""Renders the voice lines of every voiced NPC: one Ogg Vorbis file per line and voice language.

Usage: tools/voice.sh [npc id ...] [--prune] [--dry-run]   (runs this with VOICE_PYTHON, which needs numpy and
soundfile, e.g. the VoxCPM environment; env: VOICE_COMFYUI_URL, the voice ComfyUI with Qwen3-TTS)

An NPC is voiced once assets/voice/source/<npc id>/ holds its anchors (anchor.py): one per voice language, listed
in voice.json. Its lines are its dialogue's (the profile .tres in game/npcs/ with that id): the prompt and every
line of the greeting, the topics and the reactions (only the reactions, its radio calls, with "lines": "reactions"
in voice.json), in English (the translation keys) and translated from locale/<language>.po.
Each line is cloned from the language's anchor with Qwen3-TTS (comfy.py) and written to
assets/voice/<npc id>/<language>/<hash>.ogg, the hash being the first 16 hex digits of the SHA-256 of the English
line, so the game finds a line's file from its text (`VoiceLines`). manifest.json next to the anchors records what
made each file (the text spoken, the anchor's hash, the model, the seed); a file whose line, anchor or model
changed is rendered again. Files of lines that are gone are listed; --prune deletes them.

A line that came out badly gets another seed: add "<hash>": <seed> to "reroll" under its language in voice.json.
"""

import hashlib
import json
import os
import pathlib
import re
import sys
import tempfile

import comfy
import numpy as np
import soundfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets" / "voice" / "source"
OUT = ROOT / "assets" / "voice"
ENGINE = "qwen3"
NAMES = {"en": "English", "de": "German"}
# The level every line is brought to (RMS, dBFS), never louder than PEAK at its peak. TBD (playtest).
LEVEL = -20.0
PEAK = -1.0
# Silence below this level (dBFS) is trimmed from both ends, keeping PAD seconds.
SILENCE = -45.0
PAD = 0.08


def line_hash(english: str) -> str:
    return hashlib.sha256(english.encode("utf-8")).hexdigest()[:16]


def file_hash(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def default_prompt() -> str:
    script = (ROOT / "game" / "npcs" / "dialogue.gd").read_text(encoding="utf-8")
    return json.loads(re.search(r"var prompt: String = (\".*\")", script).group(1))


def npc_lines(npc: str, reactions_only: bool = False) -> list[str]:
    """The NPC's lines in English: the prompt, then the greeting's, every topic's and reaction's, in file order;
    only the reactions' with reactions_only."""
    for path in sorted((ROOT / "game" / "npcs").rglob("*.tres")):
        text = path.read_text(encoding="utf-8")
        resource = text[text.rfind("[resource]") :]
        if re.search(rf'^id = &"{re.escape(npc)}"$', resource, re.MULTILINE):
            break
    else:
        raise SystemExit(f"No NPC profile with id {npc} in game/npcs/")
    prompt = re.search(r'^prompt = (".*")$', text, re.MULTILINE)
    lines = [] if reactions_only else [json.loads(prompt.group(1)) if prompt else default_prompt()]
    for block in re.split(r"\n(?=\[)", text):
        # A reaction's block names its event.
        if reactions_only and not re.search(r"^event = ", block, re.MULTILINE):
            continue
        for found in re.finditer(r"^lines = Array\[String\]\((\[.*\])\)$", block, re.MULTILINE):
            lines += json.loads(found.group(1))
    return list(dict.fromkeys(lines))


def translations(language: str) -> dict[str, str]:
    """msgid -> msgstr of locale/<language>.po (entries without a context)."""
    entries: dict[str, str] = {}
    po = (ROOT / "locale" / f"{language}.po").read_text(encoding="utf-8")
    for block in po.split("\n\n"):
        if "msgctxt" in block:
            continue
        found = re.search(r'^msgid ((?:".*"\n?)+)^msgstr ((?:".*"\n?)+)', block + "\n", re.MULTILINE)
        if found:

            def join(part: str) -> str:
                return "".join(json.loads(s) for s in re.findall(r'^".*"$', part, re.MULTILINE))

            entries[join(found.group(1))] = join(found.group(2))
    return entries


def finish(source: str, out: pathlib.Path) -> None:
    """Trims the silence at both ends, levels the line and writes it as Ogg Vorbis."""
    audio, rate = soundfile.read(source, dtype="float32")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    loud = np.flatnonzero(np.abs(audio) > 10 ** (SILENCE / 20))
    if loud.size:
        pad = int(PAD * rate)
        audio = audio[max(loud[0] - pad, 0) : loud[-1] + pad]
    rms = float(np.sqrt(np.mean(audio**2))) or 1e-9
    gain = min(10 ** (LEVEL / 20) / rms, 10 ** (PEAK / 20) / (float(np.max(np.abs(audio))) or 1e-9))
    out.parent.mkdir(parents=True, exist_ok=True)
    soundfile.write(out, audio * gain, rate, format="OGG", subtype="VORBIS")


def render(npc: str, prune: bool, dry_run: bool) -> None:
    folder = SOURCE / npc
    voice = json.loads((folder / "voice.json").read_text(encoding="utf-8"))
    scope = voice.pop("lines", "all")
    manifest_path = folder / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    lines = npc_lines(npc, scope == "reactions")
    model = comfy.CLONERS[ENGINE][1]
    for language, anchor in voice.items():
        spoken = {line: line for line in lines} if language == "en" else translations(language)
        anchor_path = folder / anchor["anchor"]
        anchor_id = file_hash(anchor_path)
        done = manifest.setdefault(language, {})
        uploaded = None
        wanted = set()
        for line in lines:
            key = line_hash(line)
            wanted.add(key)
            text = spoken.get(line, "")
            if not text:
                print(f"{npc}/{language}: no translation for {line!r}", flush=True)
                continue
            out = OUT / npc / language / f"{key}.ogg"
            seed = int(anchor.get("reroll", {}).get(key, 1))
            made = {"text": text, "anchor": anchor_id, "model": model, "seed": seed}
            if out.exists() and done.get(key) == made:
                continue
            if dry_run:
                print(f"would render {out.relative_to(ROOT).as_posix()}: {text}", flush=True)
                continue
            uploaded = uploaded or comfy.upload(str(anchor_path), f"lodestorm_voice_{npc}_{language}.flac")
            with tempfile.TemporaryDirectory() as tmp:
                raw = os.path.join(tmp, "line.flac")
                seconds = comfy.clone(ENGINE, raw, seed, uploaded, anchor["text"], text, NAMES[language])
                finish(raw, out)
            done[key] = made
            manifest_path.write_text(
                json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
                encoding="utf-8",
                newline="\n",
            )
            print(f"{out.relative_to(ROOT).as_posix()} ({seconds:.1f}s): {text}", flush=True)
        for old in sorted((OUT / npc / language).glob("*.ogg")):
            if old.stem in wanted:
                continue
            if prune and not dry_run:
                old.unlink()
                pathlib.Path(f"{old}.import").unlink(missing_ok=True)
                done.pop(old.stem, None)
                print(f"pruned {old.relative_to(ROOT).as_posix()}", flush=True)
            else:
                print(f"stale (no line any more): {old.relative_to(ROOT).as_posix()}", flush=True)
    if not dry_run:
        manifest_path.write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
        )


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    npcs = args or sorted(p.name for p in SOURCE.iterdir() if (p / "voice.json").exists())
    for name in npcs:
        render(name, "--prune" in sys.argv, "--dry-run" in sys.argv)
