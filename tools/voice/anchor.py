"""Makes a rated take an NPC's voice anchor for one voice language.

Usage: python tools/voice/anchor.py <npc id> <language> <round>/<character>/<file>
e.g.   python tools/voice/anchor.py quartermaster en round1b/brannik/qwen3_s1.flac

Copies the take from local/voice/ to assets/voice/source/<npc id>/anchor_<language>.flac and records where it came
from (model, seed, the description and the text it speaks) in that folder's voice.json, which render.py reads.
Every line of the NPC in that language is cloned from this anchor; changing it marks them all stale.
"""

import json
import shutil
import sys

import db

SOURCE = db.ROOT.parents[1] / "assets" / "voice" / "source"


def main(npc: str, language: str, take_path: str) -> None:
    round_name, character, file = take_path.split("/")
    con = db.connect()
    take = con.execute(
        "select * from takes where round = ? and character = ? and file = ?", (round_name, character, file)
    ).fetchone()
    if not take:
        raise SystemExit(f"No take {take_path} in {db.PATH}")
    folder = SOURCE / npc
    folder.mkdir(parents=True, exist_ok=True)
    # Godot must not import the anchors (they're sources, not game audio)
    (SOURCE / ".gdignore").touch()
    shutil.copyfile(db.ROOT / round_name / character / file, folder / f"anchor_{language}.flac")
    info_path = folder / "voice.json"
    info = json.loads(info_path.read_text(encoding="utf-8")) if info_path.exists() else {}
    info[language] = {
        "anchor": f"anchor_{language}.flac",
        "text": take["text"],
        "description": take["description"],
        "model": take["model"],
        "seed": take["seed"],
        "picked_from": take_path,
        "picked": db.now()[:10],
    }
    info_path.write_text(json.dumps(info, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print(f"{folder / f'anchor_{language}.flac'} <- {take_path}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
