# Lodestorm

Dark, realistic sci-fi 3D isometric mining/action game (Godot, version in `.godot-version`; GDScript). Desktop first, VR (Steam Frame) support, solo with optional 4-player co-op.

- Design: `docs/design/` (the game as built, one file per topic); decided but not built: `docs/planned/` (one file per topic, moved into `docs/design/` once built)
- Milestones: `docs/PLAN.md` (Done / Todo); current: **M4 (progression & quests)**, in progress
- Technical (architecture, tooling, CI, assets, licensing, Steam): `docs/technical/` (one file per topic); traps that cost time once: `docs/technical/pitfalls.md`
- Godot editor: not on PATH, use env var `GODOT4_EDITOR` (e.g. `"$GODOT4_EDITOR" --headless ...`)

## Working agreements

- Keep the docs up to date when decisions change: a design round's result goes to `docs/planned/`, a built PR moves its part into `docs/design/` and ticks its line in `PLAN.md`; values marked **TBD (playtest)** are tuned later, don't invent final numbers.
- Static typing everywhere; every GDScript warning is an error (a script with one doesn't load); code must pass `tools/lint.sh` (`gdformat --check`, `gdlint`; `ruff` for the Python asset scripts) and `tools/test.sh` (GUT, headless). CI enforces both; no git hooks. Judge `tools/lint.sh` by its exit code: its last line can read "All checks passed!" after an earlier check failed.
- Tests: run the scripts a change touches, one per call (`tools/test.sh -gselect=test_foo.gd`; `-gtest=a.gd,b.gd` still runs everything); grep `tests/` for the classes, nodes and resources you changed, not just the matching folder. CI runs the whole suite.
- gdlint caps classes at 20 public methods and files at 1000 lines: check before adding to a big class (`Player`, `Alien`, `Npc`, `GeneratedLocation`, ...); grow it through components or a split.
- Player-facing text goes through translations (`tr()` or a node's text): after adding or changing texts run `tools/translations.sh` and translate them in `locale/de.po` (see `docs/technical/localization.md`). NPC lines follow `docs/design/localization-and-voice.md` (Writing lines).
- Must run on Windows (Git Bash), Linux and macOS: POSIX shell scripts, no machine-specific paths, LF line endings (see `docs/technical/development.md`, Cross-platform development).
- Versions have a single source of truth and are referenced, never repeated: Godot in `.godot-version`, godot-ai in `.mcp.json` (its `addons/godot_ai/plugin.cfg` must match), gdtoolkit and ruff in `requirements-dev.txt`, GUT in `addons/gut/plugin.cfg`.
- No 2D HUD: game information lives in the world or on the player; menus are 3D panels in the world (see `docs/design/ui.md`), new ones as stations (`docs/technical/menus.md`). 2D only for developer tools.
- Gitignored work folders: `local/` for files that last (drafts, notes, PR text), `tmp/` for scratch output (keep its `.gdignore`).
- Commit messages: one Conventional Commits title under 64 characters, no body, no trailers. `main` is protected (PRs only, squash merge), so the PR title becomes the commit and follows the same format.
- License is CC BY-NC-SA 4.0 (source-available, not OSI open source); contributions require the CLA.

## Design rules

- Design for the real size, not a default of three (10–15 ores, 50–100 skills, about eight crew, many weapons and regions): data, layout and tests scale from the first iteration (`docs/design/README.md`).
- Weapon and alien names may be renamed before release: they live only in `display_name`, never in code, ids, flags or save keys.
- No save migrations before 1.0: a format change raises `SaveGame.VERSION`, and older saves start fresh.
- No spider-like creatures (arachnophobia): no bulbous bodies on long thin legs; short, sturdy or tucked legs instead.
- Docs, comments and PR text describe Lodestorm in its own words: don't name other games or repos used as inspiration.

## MCP servers

Setup in `docs/technical/development.md` (MCP servers).

- **godot-ai** (editor must be open): scene/script editing, project settings, `editor_screenshot` (viewport, or `source="game"` while running), logs, `project_run`, `game_eval`. The running game's frame can only be captured while its loop runs. Prefer it over editing `project.godot` by hand while the editor is open (the editor may overwrite the file).
- **blender** (Blender running with the MCP add-on): asset work. Without the GUI, run scripts headless with `tools/blender.sh <script> [args]` (env var `BLENDER`); that also lets several agents work in parallel on separate files. Asset scripts: see `docs/technical/assets.md`.

## Pitfalls

The most common ones; the rest is in `docs/technical/pitfalls.md` (also how to write a screenshot probe).

- **Imports are async.** After adding or copying big `.glb`s, wait until every `<file>.glb.import` exists before running tests ("No loader found" otherwise); reimport copied or renamed files (stale UID warnings). Don't scan while Blender is still writing files.
- **Hand-written `.tscn`/`.tres` need UIDs** (own and on every `ext_resource`): run `tools/uids.sh` after creating or patching them outside the editor.
- **Typed loops:** type loop variables over untyped arrays (`for p: Vector3 in [...]`) and annotate values read from Variants, or scripts fail to parse with strict typing warnings.
- **GUT skips scripts that don't parse** ("does not extend GutTest"): a missing test count means a parse error, read the line above it.
- **SceneTree scripts (`-s`) compile before autoloads exist:** game classes refer to the `Sfx` autoload, so a probe must `load()` its game code at runtime from a thin loader script (see `docs/technical/audio.md`). Run windowed probes under `timeout`, and stop a stuck one by its process id, never every Godot process (the editor is the same executable).
- **Shader built-ins aren't visible in helper functions** (`VIEW_INDEX`, `INV_VIEW_MATRIX`): pass them in as parameters.
- **A SubViewport doesn't inherit `use_occlusion_culling`** from the project setting; set it on the viewport.
- **Don't instance a `.glb` just to read its mesh** (`instantiate()` + `free()` can leave meshes rendering); read it from `PackedScene.get_state()`.
- **Bash tool:** for anything longer than a few lines of Python, write a file in `tmp/` and run it; long heredocs with quotes break.
- **Python on Windows writes CRLF and reads cp1252:** use `read_text(encoding="utf-8")` and `write_text(..., encoding="utf-8", newline="\n")` (same for `open`) so files stay UTF-8 and LF. `gdformat <file>` (in place) does it too: convert back to LF afterwards.
