# Lodestorm

Dark, realistic sci-fi 3D isometric mining/action game (Godot, version in `.godot-version`; GDScript). Desktop first, VR (Steam Frame) support, solo with optional 4-player co-op.

- Design: `docs/GAME_DESIGN.md`
- Milestones: `docs/PLAN.md` — current: **M4 (progression & quests)**, in progress
- Tooling, CI, licensing, Steam: `docs/TECHNICAL.md`
- Godot editor: not on PATH, use env var `GODOT4_EDITOR` (e.g. `"$GODOT4_EDITOR" --headless ...`)

## Working agreements

- Keep the docs up to date when decisions change; values marked **TBD (playtest)** are tuned later, don't invent final numbers.
- Static typing everywhere; every GDScript warning is an error (a script with one doesn't load); code must pass `tools/lint.sh` (`gdformat --check`, `gdlint`; `ruff` for the Python asset scripts) and `tools/test.sh` (GUT, headless). CI enforces both; no git hooks.
- Must run on Windows (Git Bash), Linux and macOS: POSIX shell scripts, no machine-specific paths, LF line endings — see `docs/TECHNICAL.md` (Cross-platform development).
- Versions have a single source of truth and are referenced, never repeated: Godot in `.godot-version`, godot-ai in `.mcp.json` (its `addons/godot_ai/plugin.cfg` must match), gdtoolkit and ruff in `requirements-dev.txt`, GUT in `addons/gut/plugin.cfg`.
- No 2D HUD: game information lives in the world or on the player; menus are 3D panels in the world (see `docs/GAME_DESIGN.md`, UI). 2D only for developer tools.
- Commit messages: one Conventional Commits title under 64 characters, no body, no trailers. `main` is protected (PRs only, squash merge), so the PR title becomes the commit and follows the same format.
- License is CC BY-NC-SA 4.0 (source-available, not OSI open source); contributions require the CLA.

## MCP servers

Setup in `docs/TECHNICAL.md` (MCP servers).

- **godot-ai** (editor must be open): scene/script editing, project settings, `editor_screenshot` (viewport, or `source="game"` while running), logs, `project_run`, `game_eval`. The running game's frame can only be captured while its loop runs. Prefer it over editing `project.godot` by hand while the editor is open (the editor may overwrite the file).
- **blender** (Blender running with the MCP add-on): asset work. Without the GUI, run scripts headless with `tools/blender.sh <script> [args]` (env var `BLENDER`); that also lets several agents work in parallel on separate files. Asset scripts: see `docs/TECHNICAL.md` (Asset pipeline).

## Pitfalls

- **Imports are async.** After adding or copying big `.glb`s, wait until every `<file>.glb.import` exists before running tests ("No loader found" otherwise); reimport copied or renamed files (stale UID warnings). Don't scan while Blender is still writing files.
- **Hand-written `.tscn`/`.tres` need UIDs** (own and on every `ext_resource`): run `tools/uids.sh` after creating or patching them outside the editor.
- **Typed loops:** type loop variables over untyped arrays (`for p: Vector3 in [...]`) and annotate values read from Variants, or scripts fail to parse with strict typing warnings.
- **Shader built-ins aren't visible in helper functions** (`VIEW_INDEX`, `INV_VIEW_MATRIX`): pass them in as parameters.
- **A SubViewport doesn't inherit `use_occlusion_culling`** from the project setting; set it on the viewport.
- **Don't instance a `.glb` just to read its mesh** (`instantiate()` + `free()` can leave meshes rendering); read it from `PackedScene.get_state()`.
- **Bash tool:** for anything longer than a few lines of Python, write a file in `tmp/` and run it; long heredocs with quotes break.
- **Python on Windows writes CRLF and reads cp1252:** use `read_text(encoding="utf-8")` and `write_text(..., encoding="utf-8", newline="\n")` (same for `open`) so files stay UTF-8 and LF. `gdformat <file>` (in place) does it too: convert back to LF afterwards.
