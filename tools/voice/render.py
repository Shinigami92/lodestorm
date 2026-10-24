"""Renders the voice lines of every voiced NPC: one Ogg Vorbis file per line and voice language.

Usage: tools/voice.sh [npc id ...] [--prune] [--dry-run]   (runs this with VOICE_PYTHON, which needs numpy and
soundfile, e.g. the VoxCPM environment; env: VOICE_COMFYUI_URL, the voice ComfyUI with Qwen3-TTS)

Which lines a voiced NPC has and where their recordings go: see lines.py. Each line is cloned from the language's
anchor with Qwen3-TTS (comfy.py), trimmed and leveled; manifest.json next to the anchors records what made each
file (the text spoken, the anchor's hash, the model, the seed), and a file whose line, anchor or model changed is
rendered again. Files of lines that are gone are listed; --prune deletes them. tools/voice_status.sh lists what's
missing and what's stale without rendering (no GPU needed).

A line that came out badly gets another seed: add "<hash>": <seed> to "reroll" under its language in voice.json.
"""

import os
import pathlib
import sys
import tempfile

import comfy
import lines
import numpy as np
import soundfile

NAMES = {"en": "English", "de": "German"}
# The level every line is brought to (RMS, dBFS), never louder than PEAK at its peak. TBD (playtest).
LEVEL = -20.0
PEAK = -1.0
# Silence below this level (dBFS) is trimmed from both ends, keeping PAD seconds.
SILENCE = -45.0
PAD = 0.08


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
    manifest = lines.load_manifest(npc)
    for language in lines.plan(npc, manifest):
        uploaded = None
        for line in language.lines:
            if not line.text:
                print(f"{npc}/{language.language}: no translation for {line.english!r}", flush=True)
                continue
            shown = line.out.relative_to(lines.ROOT).as_posix()
            if line.out.exists() and language.done.get(line.key) == line.made:
                continue
            if dry_run:
                print(f"would render {shown}: {line.text}", flush=True)
                continue
            name = f"lodestorm_voice_{npc}_{language.language}.flac"
            uploaded = uploaded or comfy.upload(str(language.anchor_path), name)
            with tempfile.TemporaryDirectory() as tmp:
                raw = os.path.join(tmp, "line.flac")
                seconds = comfy.clone(
                    lines.ENGINE,
                    raw,
                    line.made["seed"],
                    uploaded,
                    language.anchor["text"],
                    line.text,
                    NAMES[language.language],
                )
                finish(raw, line.out)
            language.done[line.key] = line.made
            lines.save_manifest(npc, manifest)
            print(f"{shown} ({seconds:.1f}s): {line.text}", flush=True)
        if prune and not dry_run:
            for old in lines.prune(language):
                print(f"pruned {old.relative_to(lines.ROOT).as_posix()}", flush=True)
        else:
            for old in language.stale():
                print(f"stale (no line any more): {old.relative_to(lines.ROOT).as_posix()}", flush=True)
    if not dry_run:
        lines.save_manifest(npc, manifest)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    for name in args or lines.voiced():
        render(name, "--prune" in sys.argv, "--dry-run" in sys.argv)
