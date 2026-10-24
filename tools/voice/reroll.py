"""Renders one voice line of an NPC with other seeds, to pick a better take by ear (rate.py).

Usage: <VOICE_PYTHON> tools/voice/reroll.py <npc id> <language> "<English line>" [seed ...]   (default seeds 1-6)

The takes go to local/voice/reroll-<npc id>-<language>/<npc id>/seed<N>.flac (seed 1 is the take in the game, for
comparison) and into the voice database. Once one is picked, add "<hash>": <seed> to "reroll" under the language
in assets/voice/source/<npc id>/voice.json and run tools/voice.sh, which renders that line again with it.
"""

import json
import sys

import comfy
import render

import db


def main(npc: str, language: str, english: str, seeds: list[int]) -> None:
    folder = render.SOURCE / npc
    anchor = json.loads((folder / "voice.json").read_text(encoding="utf-8"))[language]
    text = english if language == "en" else render.translations(language)[english]
    key = render.line_hash(english)
    round_name = f"reroll-{npc}-{language}"
    out = db.ROOT / round_name / npc
    out.mkdir(parents=True, exist_ok=True)
    con = db.connect()
    uploaded = comfy.upload(str(folder / anchor["anchor"]), f"lodestorm_voice_{npc}_{language}.flac")
    for seed in seeds:
        file = f"seed{seed}.flac"
        raw = out / f"raw_{file}"
        seconds = comfy.clone(render.ENGINE, str(raw), seed, uploaded, anchor["text"], text, render.NAMES[language])
        # The same finish as in the game (trimmed, leveled), as FLAC for the listening page
        render.finish(str(raw), out / f"seed{seed}.ogg")
        audio, rate = render.soundfile.read(out / f"seed{seed}.ogg", dtype="float32")
        render.soundfile.write(out / file, audio, rate)
        (out / f"seed{seed}.ogg").unlink()
        raw.unlink()
        con.execute(
            "insert or replace into takes values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                round_name,
                npc,
                file,
                render.ENGINE,
                render.comfy.CLONERS[render.ENGINE][1],
                seed,
                language,
                anchor["description"],
                text,
                f"line {key}, anchor {anchor['picked_from']}",
                seconds,
                db.now(),
            ),
        )
        con.commit()
        print(f"{round_name}/{npc}/{file} ({seconds:.1f}s)", flush=True)


if __name__ == "__main__":
    args = sys.argv[1:]
    main(args[0], args[1], args[2], [int(s) for s in args[3:]] or [1, 2, 3, 4, 5, 6])
