"""Voice conversion: give a round's takes the voice of a character's anchor, keeping how they speak.

Usage: python tools/voice/convert.py <round> <character> <anchor round>/<anchor file> [pattern]   (default *_de.flac)

For a language the anchor doesn't speak natively: a native speaker's take (voice design in that language) keeps its
pronunciation, and Chatterbox's voice conversion swaps in the anchor's timbre. Each <take>.flac becomes
<take>_vc.flac in the same folder, recorded in the voice database; existing ones are skipped.
"""

import sys

import comfy

import db


def main(round_name: str, character: str, anchor_path: str, pattern: str) -> None:
    con = db.connect()
    anchor_round, anchor_file = anchor_path.split("/")
    anchor = con.execute(
        "select * from takes where round = ? and character = ? and file = ?", (anchor_round, character, anchor_file)
    ).fetchone()
    target = comfy.upload(
        str(db.ROOT / anchor_round / character / anchor_file), f"lodestorm_{character}_{anchor_round}-{anchor_file}"
    )
    folder = db.ROOT / round_name / character
    for source in sorted(folder.glob(pattern)):
        if source.stem.endswith("_vc"):
            continue
        out = folder / f"{source.stem}_vc.flac"
        if out.exists():
            continue
        take = con.execute(
            "select * from takes where round = ? and character = ? and file = ?", (round_name, character, source.name)
        ).fetchone()
        uploaded = comfy.upload(str(source), f"lodestorm_{character}_{round_name}-{source.name}")
        seconds = comfy.convert(str(out), uploaded, target, anchor["text"])
        con.execute(
            "insert or replace into takes values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                round_name,
                character,
                out.name,
                f"{take['engine']}+vc",
                f"{take['model']} + {comfy.CLONERS['chatterbox'][1]} voice conversion",
                take["seed"],
                take["language"],
                take["description"],
                take["text"],
                f"vc to {anchor_path}",
                seconds,
                db.now(),
            ),
        )
        con.commit()
        print(f"{round_name}/{character}/{out.name} ({seconds:.1f}s)", flush=True)


if __name__ == "__main__":
    main(*sys.argv[1:4], sys.argv[4] if len(sys.argv) > 4 else "*_de.flac")
