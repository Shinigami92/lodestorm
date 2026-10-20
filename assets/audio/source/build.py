"""Builds the game's sound effects from their recipes (see synth.py and the group modules).

    python assets/audio/source/build.py [name ...]
        Builds the take the game uses of every sound (or of the named ones, e.g.
        weapons/blaster_shot) into assets/audio/sfx/<group>/<name>_<variant>.wav and lists every
        sound with the recordings it uses in manifest.json.
    python assets/audio/source/build.py --takes DIR [name ...]
        Builds every take into DIR with a listening page (DIR/listen.html) to pick from.

Deterministic: the same recipes give the same files. 16-bit mono WAV; Godot compresses them on
import (QOA).

The built sounds are placeholders: a better one replaces the files under the same names. Its entry
in manifest.json then says how it was made instead of "build.py" (`made_by`, e.g. the AI model or
"recorded", with the recordings it uses), and it is never built again; its recipe can go.
"""

import argparse
import html
import json
import random
import struct
import sys
import wave
import zlib
from pathlib import Path

import player  # noqa: F401  (registers its recipes)
import weapons  # noqa: F401
from synth import RATE, RECIPES, Recipe, Signal, finish

SOURCE = Path(__file__).resolve().parent
SFX = SOURCE.parent / "sfx"
MANIFEST = SOURCE / "manifest.json"
# Licenses a recording may have (the game is sold: no NC, ND or SA); CC-BY needs a credit
ALLOWED_LICENSES = ("CC0-1.0", "CC-BY-4.0")


def render(recipe: Recipe, take: str, variant: int) -> Signal:
    rng = random.Random(zlib.crc32(f"{recipe.name}/{take}/{variant}".encode()))
    return finish(recipe.make(rng, take, variant), recipe.peak_db)


def write_wav(path: Path, signal: Signal) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(struct.pack("<h", max(-32767, min(32767, round(s * 32767)))) for s in signal)
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(frames)


def load_manifest() -> dict:
    if not MANIFEST.exists():
        return {"recordings": {}, "sounds": {}}
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


BUILT = "build.py"


def replaced(manifest: dict) -> dict[str, dict]:
    """The sounds made some other way (never built again), by name."""
    return {name: entry for name, entry in manifest["sounds"].items() if entry.get("made_by") != BUILT}


def check_recordings(manifest: dict) -> list[str]:
    """Problems with the recordings the sounds use: missing from the manifest, a license not
    allowed, or the file missing."""
    uses = {recipe.name: recipe.recordings for recipe in RECIPES.values()}
    uses.update({name: entry.get("recordings", []) for name, entry in replaced(manifest).items()})
    problems = []
    for name, recordings in uses.items():
        for recording in recordings:
            entry = manifest["recordings"].get(recording)
            if not entry:
                problems.append(f"{name}: {recording} is not in manifest.json")
            elif entry.get("license") not in ALLOWED_LICENSES:
                problems.append(f"{recording}: license {entry.get('license')} is not allowed")
            if not (SOURCE / "recordings" / recording).exists():
                problems.append(f"{name}: recordings/{recording} is missing")
    return problems


def build(recipes: list[Recipe], manifest: dict) -> None:
    kept = replaced(manifest)
    for recipe in recipes:
        if recipe.name in kept:
            print(f"kept {recipe.name} (made by {kept[recipe.name].get('made_by')})")
            continue
        for variant in range(1, recipe.variants + 1):
            write_wav(SFX / f"{recipe.name}_{variant}.wav", render(recipe, recipe.take, variant))
        # Variants the recipe no longer has
        for stale in SFX.glob(f"{recipe.name}_*.wav"):
            number = stale.stem.rsplit("_", 1)[1]
            if number.isdigit() and int(number) > recipe.variants:
                stale.unlink()
                stale.with_name(stale.name + ".import").unlink(missing_ok=True)
        print(f"built {recipe.name} (take {recipe.take}, {recipe.variants} variants)")


def write_manifest(manifest: dict) -> None:
    sounds = {
        name: {"made_by": BUILT, "variants": recipe.variants, "recordings": list(recipe.recordings)}
        for name, recipe in RECIPES.items()
    }
    sounds.update(replaced(manifest))
    manifest["sounds"] = dict(sorted(sounds.items()))
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")


def build_takes(recipes: list[Recipe], directory: Path) -> None:
    rows = []
    for recipe in recipes:
        takes = []
        for take in recipe.takes:
            players = []
            for variant in range(1, recipe.variants + 1):
                file = f"{recipe.name}/{take}_{variant}.wav"
                write_wav(directory / file, render(recipe, take, variant))
                players.append(f'<audio controls preload="none" src="{file}"></audio>')
            used = " (in the game)" if take == recipe.take else ""
            takes.append(
                f'<label class="take"><input type="radio" name="{recipe.name}" value="{take}">'
                f"<b>{take}{used}</b> {''.join(players)}</label>"
            )
        rows.append(
            f'<section data-name="{recipe.name}"><h2>{recipe.name}</h2>'
            f"<p>{html.escape(recipe.description)}</p>{''.join(takes)}"
            f'<input class="note" placeholder="note"></section>'
        )
        print(f"takes {recipe.name}: {recipe.takes}")
    (directory / "listen.html").write_text(PAGE.replace("{rows}", "\n".join(rows)), encoding="utf-8", newline="\n")
    print(f"open {directory / 'listen.html'}")


PAGE = """<!doctype html>
<meta charset="utf-8">
<title>Lodestorm sound takes</title>
<style>
body { background: #15171a; color: #d8d8d8; font: 15px system-ui, sans-serif; margin: 2em auto; max-width: 70em; }
section { border-top: 1px solid #333; padding: 0.6em 0; }
h2 { font-size: 1.05em; margin: 0.2em 0; color: #f0a040; }
p { margin: 0.2em 0 0.5em; color: #a0a0a0; }
.take { display: flex; align-items: center; gap: 0.6em; margin: 0.2em 0; }
.take b { width: 9em; }
audio { height: 2em; }
.note { width: 30em; background: #222; color: #ddd; border: 1px solid #444; }
textarea { width: 100%; height: 12em; background: #222; color: #ddd; }
</style>
<h1>Sound takes</h1>
<p>Pick a take per sound (add a note if it needs changes), then copy the summary at the bottom.</p>
{rows}
<h2>Summary</h2>
<textarea id="summary" readonly></textarea>
<script>
const KEY = "lodestorm-takes";
let saved = {};
try { saved = JSON.parse(localStorage.getItem(KEY) || "{}"); } catch (e) {}
const sections = [...document.querySelectorAll("section")];
function update() {
  const lines = [];
  for (const section of sections) {
    const name = section.dataset.name;
    const picked = section.querySelector("input[type=radio]:checked");
    const note = section.querySelector(".note").value;
    saved[name] = { take: picked ? picked.value : "", note };
    if (picked || note) lines.push(name + ": " + (picked ? picked.value : "-") + (note ? " (" + note + ")" : ""));
  }
  document.getElementById("summary").value = lines.join("\\n");
  try { localStorage.setItem(KEY, JSON.stringify(saved)); } catch (e) {}
}
for (const section of sections) {
  const entry = saved[section.dataset.name] || {};
  for (const radio of section.querySelectorAll("input[type=radio]")) radio.checked = radio.value === entry.take;
  section.querySelector(".note").value = entry.note || "";
  section.addEventListener("input", update);
}
update();
</script>
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*", help="sounds to build (default: all)")
    parser.add_argument("--takes", type=Path, help="build every take into this directory, with listen.html")
    args = parser.parse_args()
    unknown = [name for name in args.names if name not in RECIPES]
    if unknown:
        sys.exit(f"unknown sounds: {', '.join(unknown)} (known: {', '.join(sorted(RECIPES))})")
    recipes = [RECIPES[name] for name in args.names] if args.names else list(RECIPES.values())
    manifest = load_manifest()
    problems = check_recordings(manifest)
    if problems:
        sys.exit("\n".join(problems))
    if args.takes:
        build_takes(recipes, args.takes)
        return
    build(recipes, manifest)
    write_manifest(manifest)


if __name__ == "__main__":
    main()
