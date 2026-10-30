"""What the voiced NPCs say and where their recordings go: shared by render.py, status.py, rate.py and reroll.py
(standard library only).

An NPC is voiced once assets/voice/source/<npc id>/ holds its anchors (anchor.py): one per voice language, listed
in voice.json. Its lines are what the game says it speaks (`VoiceLines.lines_by_speaker`, written by
tools/voice_lines.gd, run headless with GODOT4_EDITOR): its profile's (the prompts, the greeting, the topics, the
tour, the reactions, the remarks) and lines of other files it says (a quest's hand-in), in English (the translation
keys) and translated from locale/<language>.po. A line's recording is assets/voice/<npc id>/<language>/<hash>.ogg,
the hash being the first 16 hex digits of the SHA-256 of the English line, so the game finds a line's file from its
text (`VoiceLines`). manifest.json next to the anchors records what made each file (the text spoken, the anchor's
hash, the model, the seed).
"""

import dataclasses
import functools
import hashlib
import json
import os
import pathlib
import re
import subprocess

import comfy

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets" / "voice" / "source"
OUT = ROOT / "assets" / "voice"
ENGINE = "qwen3"


@dataclasses.dataclass
class Line:
    """One line of an NPC in one voice language."""

    english: str
    # The first 16 hex digits of the SHA-256 of the English line: the recording's name.
    key: str
    # What's spoken in the language ("" without a translation).
    text: str
    # The recording.
    out: pathlib.Path
    # What makes the recording (the manifest's entry once it's rendered).
    made: dict


@dataclasses.dataclass
class Language:
    """An NPC's lines in one voice language, and what its manifest says is rendered."""

    npc: str
    language: str
    anchor: dict
    anchor_path: pathlib.Path
    lines: list[Line]
    # The manifest's entries of this language (hash -> what made the file).
    done: dict

    def stale(self) -> list[pathlib.Path]:
        """Recordings whose line is gone (changed or removed)."""
        wanted = {line.key for line in self.lines}
        return [old for old in sorted((OUT / self.npc / self.language).glob("*.ogg")) if old.stem not in wanted]


def line_hash(english: str) -> str:
    return hashlib.sha256(english.encode("utf-8")).hexdigest()[:16]


def file_hash(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


@functools.cache
def speakers() -> dict[str, dict]:
    """Every NPC who says lines, as the game finds them: id -> {"name", "role", "lines"} (the English lines in the
    game's order). Runs tools/voice_lines.gd headless once per tool run."""
    godot = os.environ.get("GODOT4_EDITOR")
    if not godot:
        raise SystemExit("Set GODOT4_EDITOR to the Godot executable: the voice tools ask the game for its lines")
    out = ROOT / "tmp" / "voice_lines.json"
    out.unlink(missing_ok=True)
    run = subprocess.run(
        [godot, "--headless", "--path", str(ROOT), "-s", "tools/voice_lines.gd", "--", f"--out={out}"],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if run.returncode != 0 or not out.exists():
        raise SystemExit(f"tools/voice_lines.gd failed ({run.returncode}):\n{run.stdout}{run.stderr}")
    return json.loads(out.read_text(encoding="utf-8"))


def npc_lines(npc: str) -> list[str]:
    """The NPC's lines in English, in the game's order."""
    if npc not in speakers():
        raise SystemExit(f"No lines of {npc}: no NPC profile with that id in game/npcs/, or it says nothing")
    return speakers()[npc]["lines"]


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


def voiced() -> list[str]:
    """The ids of the NPCs with anchors."""
    return sorted(p.name for p in SOURCE.iterdir() if (p / "voice.json").exists())


def manifest_path(npc: str) -> pathlib.Path:
    return SOURCE / npc / "manifest.json"


def load_manifest(npc: str) -> dict:
    path = manifest_path(npc)
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def save_manifest(npc: str, manifest: dict) -> None:
    manifest_path(npc).write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )


def plan(npc: str, manifest: dict) -> list[Language]:
    """What a voiced NPC's recordings should be, per voice language, with `manifest`'s entries (filled in place)."""
    folder = SOURCE / npc
    voice = json.loads((folder / "voice.json").read_text(encoding="utf-8"))
    english_lines = npc_lines(npc)
    model = comfy.CLONERS[ENGINE][1]
    languages = []
    for language, anchor in voice.items():
        spoken = {line: line for line in english_lines} if language == "en" else translations(language)
        anchor_path = folder / anchor["anchor"]
        anchor_id = file_hash(anchor_path)
        lines = []
        for english in english_lines:
            key = line_hash(english)
            text = spoken.get(english, "")
            seed = int(anchor.get("reroll", {}).get(key, 1))
            made = {"text": text, "anchor": anchor_id, "model": model, "seed": seed}
            lines.append(Line(english, key, text, OUT / npc / language / f"{key}.ogg", made))
        languages.append(Language(npc, language, anchor, anchor_path, lines, manifest.setdefault(language, {})))
    return languages


def prune(language: Language) -> list[pathlib.Path]:
    """Deletes the recordings whose line is gone (with their .import) and their manifest entries; returns them."""
    gone = language.stale()
    for old in gone:
        old.unlink()
        pathlib.Path(f"{old}.import").unlink(missing_ok=True)
        language.done.pop(old.stem, None)
    return gone
