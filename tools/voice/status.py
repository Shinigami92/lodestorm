"""Lists what the voice recordings lack and what they have too much of, without rendering (no GPU needed).

Usage: tools/voice_status.sh [npc id ...] [--prune] [--unvoiced]

For every voiced NPC (see lines.py) and voice language:
- missing: a line without its recording (new, or changed: a changed line gets a new hash);
- outdated: a recording made from something else than now (its text, translation, anchor, model or seed changed);
- untranslated: a line without its translation in locale/<language>.po;
- stale: a recording whose line is gone (changed or removed), with the text it was made from; an .import left
  without its recording; a manifest entry whose line is gone.
Missing and outdated ones are rendered with tools/voice.sh; --prune deletes the stale ones (files and manifest
entries). NPCs without anchors are listed with how many lines they have (--unvoiced lists the lines too).
The exit code is 1 while anything is missing, outdated, untranslated or stale, else 0.
"""

import pathlib
import sys

import lines


def shorten(text: str, width: int = 90) -> str:
    return text if len(text) <= width else text[: width - 1] + "…"


def plural(count: int, word: str) -> str:
    return f"{count} {word}" if count == 1 else f"{count} {word}s"


def where(path: pathlib.Path) -> str:
    return path.relative_to(lines.ROOT).as_posix() if path.is_relative_to(lines.ROOT) else path.as_posix()


def check(npc: str, prune: bool) -> tuple[int, int, int, int]:
    """Prints an NPC's status; returns how many lines are missing, outdated, untranslated and stale."""
    manifest = lines.load_manifest(npc)
    languages = lines.plan(npc, manifest)
    voice = (lines.SOURCE / npc / "voice.json").read_text(encoding="utf-8")
    scope = ""
    if '"lines": "reactions"' in voice:
        talks = len(set(lines.npc_lines(npc)) - set(lines.npc_lines(npc, True)))
        scope = f" (radio calls only; {plural(talks, 'line')} of their talks aboard not voiced yet)"
    print(f"{npc}{scope}")
    totals = [0, 0, 0, 0]
    for language in languages:
        missing = [line for line in language.lines if line.text and not line.out.exists()]
        outdated = [
            line
            for line in language.lines
            if line.text and line.out.exists() and language.done.get(line.key) != line.made
        ]
        untranslated = [line for line in language.lines if not line.text]
        wanted = {line.key for line in language.lines}
        folder = lines.OUT / npc / language.language
        stale = language.stale()
        orphans = [
            path
            for path in sorted(folder.glob("*.ogg.import"))
            if not pathlib.Path(str(path)[: -len(".import")]).exists()
        ]
        entries = sorted(key for key in language.done if key not in wanted)
        recorded = len(language.lines) - len(missing) - len(untranslated)
        counts = [plural(len(language.lines), "line"), f"{recorded} recorded"]
        for count, name in [
            (len(missing), "missing"),
            (len(outdated), "outdated"),
            (len(untranslated), "untranslated"),
            (len(stale) + len(orphans), "stale"),
        ]:
            if count:
                counts.append(f"{count} {name}")
        print(f"  {language.language}: " + ", ".join(counts))
        for line in missing:
            print(f"    missing       {line.key}  {shorten(line.text)}")
        for line in outdated:
            before = language.done.get(line.key) or {}
            changed = [part for part in ("text", "anchor", "model", "seed") if before.get(part) != line.made[part]]
            print(f"    outdated      {line.key}  ({', '.join(changed) or 'no manifest entry'})  {shorten(line.text)}")
        for line in untranslated:
            print(f"    untranslated  {line.key}  {shorten(line.english)}")
        for old in stale:
            was = (language.done.get(old.stem) or {}).get("text", "?")
            print(f"    stale         {where(old)}  (was: {shorten(was, 70)})")
        for old in orphans:
            print(f"    stale         {where(old)}  (an .import without its recording)")
        gone = "1 manifest entry" if len(entries) == 1 else f"{len(entries)} manifest entries"
        if prune:
            for old in lines.prune(language):
                print(f"    pruned        {where(old)}")
            for old in orphans:
                old.unlink()
                print(f"    pruned        {where(old)}")
            for key in entries:
                language.done.pop(key, None)
            if entries:
                print(f"    pruned        {gone} of lines that are gone")
        elif entries:
            print(f"    stale         {gone} of lines that are gone")
        totals[0] += len(missing)
        totals[1] += len(outdated)
        totals[2] += len(untranslated)
        if not prune:
            totals[3] += len(stale) + len(orphans) + (1 if entries else 0)
    if prune:
        lines.save_manifest(npc, manifest)
    return totals[0], totals[1], totals[2], totals[3]


def unvoiced(names: list[str], listed: bool) -> None:
    """Prints the NPCs without anchors and how many lines they have."""
    rest = [npc for npc in lines.profiles() if npc not in lines.voiced() and (not names or npc in names)]
    if not rest:
        return
    print("not voiced yet (no anchors in assets/voice/source/<npc id>/):")
    for npc in rest:
        npc_lines = lines.npc_lines(npc)
        print(f"  {npc}: {plural(len(npc_lines), 'line')}")
        if listed:
            for line in npc_lines:
                print(f"    {shorten(line)}")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    prune = "--prune" in sys.argv
    voiced = [npc for npc in lines.voiced() if not args or npc in args]
    missing = outdated = untranslated = stale = 0
    for npc in voiced:
        counts = check(npc, prune)
        missing += counts[0]
        outdated += counts[1]
        untranslated += counts[2]
        stale += counts[3]
    unvoiced(args, "--unvoiced" in sys.argv)
    print(f"\n{missing} missing, {outdated} outdated, {untranslated} untranslated, {stale} stale")
    if missing or outdated:
        print("Render them: tools/voice.sh " + " ".join(voiced))
    if untranslated:
        print("Translate them first: tools/translations.sh, then locale/<language>.po")
    if stale:
        print("Delete the stale ones: tools/voice_status.sh --prune")
    return 1 if missing or outdated or untranslated or stale else 0


if __name__ == "__main__":
    sys.exit(main())
