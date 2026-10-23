"""Contact sheet of a batch's best images: python tools/concepts/sheet.py <batch> <out.jpg> [min stars, default 5]

One labeled cell per image with at least that many stars (duel winners first within a subject). Needs Pillow,
e.g. ComfyUI's bundled Python.
"""

import pathlib
import sys

from PIL import Image, ImageDraw

# ComfyUI's embedded Python doesn't put the script's folder on the path
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import db

CELL, COLS = 384, 5


def main() -> None:
    batch, out = sys.argv[1], sys.argv[2]
    min_stars = int(sys.argv[3]) if len(sys.argv) > 3 else 5
    con = db.connect()
    wins = {
        (r["subject"], r["winner"]): r["n"]
        for r in con.execute(
            "select subject, winner, count(*) as n from duels where batch = ? group by subject, winner", (batch,)
        )
    }
    rows = con.execute(
        "select subject, file from ratings where batch = ? and stars >= ? order by subject, file", (batch, min_stars)
    ).fetchall()
    picks = sorted(((r["subject"], r["file"]) for r in rows), key=lambda p: (p[0], -wins.get(p, 0), p[1]))
    sheet = Image.new("RGB", (CELL * COLS, CELL * max(1, -(-len(picks) // COLS))), "black")
    draw = ImageDraw.Draw(sheet)
    for i, (subject, file) in enumerate(picks):
        x, y = (i % COLS) * CELL, (i // COLS) * CELL
        sheet.paste(Image.open(db.ROOT / batch / subject / file).convert("RGB").resize((CELL, CELL)), (x, y))
        draw.rectangle((x, y, x + 170, y + 18), fill="black")
        draw.text((x + 4, y + 3), f"{subject}/{file[:-4]}", fill="white")
    sheet.save(out, quality=88)
    print(f"{out}: {len(picks)} images")


if __name__ == "__main__":
    main()
