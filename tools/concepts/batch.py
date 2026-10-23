"""Render a concept batch: every style x subject of tools/concepts/batches/<name>.py.

Usage: python tools/concepts/batch.py <name> [subject ...]   (env: SIZE overrides the batch's size; COMFYUI_URL)

Images go to local/concepts/<name>/<subject>/NN_<style>.png (existing ones are skipped) and each one's prompt,
seed and size into the concept database (db.py). Rate them with rate.py.

A batch module defines GROUPS, a list of (styles, subjects, seed base): styles are (name, text) pairs put in
front of every subject's prompt; an empty text means the subject carries its own style (seed-only variants).
Optional: SIZE (default 1024).
"""

import importlib
import os
import sys

import db
import gen

Styles = list[tuple[str, str]]
Group = tuple[Styles, dict[str, str], int]


def run(name: str, groups: list[Group], size: int, only: list[str]) -> None:
    con = db.connect()
    for styles, subjects, seed_base in groups:
        for subject in only or list(subjects):
            if subject not in subjects:
                continue
            folder = db.ROOT / name / subject
            folder.mkdir(parents=True, exist_ok=True)
            for i, (style, text) in enumerate(styles):
                file = f"{i + 1:02d}_{style}.png"
                if (folder / file).exists():
                    continue
                prompt = f"{text}. Subject: {subjects[subject]}." if text else subjects[subject]
                seconds = gen.generate(str(folder / file), seed_base + i, prompt, size)
                con.execute(
                    "insert or replace into images values (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (name, subject, file, style, seed_base + i, size, gen.MODEL, prompt, db.now()),
                )
                con.commit()
                print(f"{name}/{subject}/{file} ({seconds:.1f}s)", flush=True)


if __name__ == "__main__":
    module = importlib.import_module(f"batches.{sys.argv[1]}")
    size = int(os.environ.get("SIZE", getattr(module, "SIZE", 1024)))
    run(sys.argv[1], module.GROUPS, size, sys.argv[2:])
