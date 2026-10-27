# Code quality and tooling

| Tool | Purpose |
|---|---|
| [godot-gdscript-toolkit](https://github.com/Scony/godot-gdscript-toolkit) `gdlint` | Linting (naming, complexity, ordering); config in `gdlintrc` (only overrides of the defaults) |
| `gdformat` (same toolkit) | Formatting, checked with `gdformat --check`; config in `gdformatrc` |
| Godot GDScript warnings | **Every warning is an error** in the project settings (`debug/gdscript/warnings/*`), so a script with one fails to load and `tests/project/test_scripts_parse.gd` fails in CI: the default warnings (shadowing, integer division, unused variables, ...) and the typing ones Godot ignores by default (`untyped_declaration`, `unsafe_property_access`, `unsafe_method_access`, `unsafe_call_argument`). Where integer division is meant, say so with `@warning_ignore("integer_division")`. `addons/` is exempt (Godot's default `directory_rules`) |
| Unit tests | [GUT](https://github.com/bitwes/Gut) in `addons/gut/` (version in its `plugin.cfg`, must support the pinned Godot version), tests in `tests/` (`test_*.gd`, config `.gutconfig.json`), run headless |
| [ruff](https://docs.astral.sh/ruff/) | Formatting and linting of the Python scripts (Blender asset scripts, `tools/blender/`, the sound synthesis in `assets/audio/source/`); config in `ruff.toml` (ruff's default rules, only overrides; line length 120 because the asset scripts are full of coordinate tables; target: Blender's bundled Python) |
| `.editorconfig` | UTF-8, LF line endings and a final newline in every editor |

All checks are enforced by CI on every pull request (failing jobs block the merge), not by local git hooks. The same scripts run locally and in CI:

- `tools/lint.sh`: `gdformat --check` + `gdlint` over the project (`addons/`, `local/`, `tmp/` excluded in the rc files), then `ruff format --check` + `ruff check` (ruff skips what git ignores, and `addons/`) and whether the generated greybox scenes match their generators (`game/ship/hull_build.py --check`, `game/space_station/ostra/ostra_build.py --check`; the station's builder sizes the hangar's pressure frame from the tail's size in `game/ship/hull_layout.py`); `tools/lint.sh gdscript` or `tools/lint.sh python` runs only one half. gdtoolkit and ruff are pinned in `requirements-dev.txt`: `pip install -r requirements-dev.txt`, ideally in a `.venv/` (gitignored).
- `tools/test.sh`: imports the project (`tools/import.sh`: fails if the import prints any `ERROR`, e.g. an LFS pointer instead of a file), then runs GUT headless with `$GODOT4_EDITOR`, spread over `TEST_JOBS` parallel processes (default 4; each one's output is printed when all are done). `TEST_SHARD=k/n` runs only the k-th of n shares (CI runs four on parallel runners). The scripts are balanced over the processes of all shares by their durations in `tests/timings.txt`, longest first (a script missing there counts as 10 s); `TEST_REPORTS=<dir>` keeps each process's GUT JUnit report in that directory (CI uploads them as the `test-reports-<share>` artifacts, kept 30 days). `tools/timings.sh` rewrites `tests/timings.txt` from those reports: local directories, CI run IDs, or without an argument the latest three successful CI runs on `main` (needs `gh`); CI's numbers fit CI's runners best. Each script's time is its mean over the runs, since one run's times swing a lot with what shares its runner (the slowest location script took 48–87 s), and scripts that no longer exist are left out. JUnit reports leave out `before_all`, so a script that shares slow work between its tests does it in the first test that needs it. Refresh the timings after adding or splitting slow scripts. Extra arguments go to GUT in a single process instead (e.g. `-gselect=test_foo.gd`). Exits non-zero on failures.
- The slowest tests (sweeps over many generated locations) are split over several scripts so they run in parallel: their planning is in `tests/support/location_sweep.gd`, and the sweep over every region's set pieces (`tests/locations/set_piece_sweep.gd`) takes a share of the locations in each `test_set_pieces_<part>.gd` (`PARTS` of them). A script that takes much longer than the others sets the floor for the whole run: split it.
- Tests run with `--fixed-fps 60` (the physics tick rate): every frame advances exactly one physics tick and simulated time doesn't wait for the wall clock, so `wait_seconds` / `wait_physics_frames` only take as long as computing the frames. Anything that runs in real time (worker threads like location planning, the background bake of the walkable area) must be waited for with `tests/support/real_time.gd` (`await REAL_TIME.wait_until(condition, seconds)`, a wall-clock timeout; assert its result), not GUT's `wait_until`, whose seconds are simulated and run out long before a busy CI runner finishes the work. Wait for the real end state (e.g. the navigation map synced with the baked region, which also can't be queried before its first sync), not for a side effect.
- GUT fails a test on any engine error or warning logged while it runs. Engine warnings that say nothing about the code under test are let through by `tests/support/expected_engine_warnings.gd` (registered in `pre_run.gd`), only by their exact text: so far Jolt's "job system exceeded the maximum number of jobs", which it logs and waits out when every worker thread is busy (four test processes on CI's four cores, physics stepped back to back).
- GUT silently skips test scripts that fail to parse, so `tests/project/test_scripts_parse.gd` loads every project script and fails on parse or typing errors.
- `tools/uids.sh` (`tools/uids.gd`, headless) gives every scene and resource its own UID and every `ext_resource` the UID of its target, as the editor writes them, so references survive moving files; a copied file gets a new UID. Run it after writing or patching `.tscn`/`.tres` files without the editor; `tests/project/test_resource_uids.gd` fails until then.
- Tests that need the map get it from `tests/support/map_fixture.gd`: the main map with the small hand-built test location instead of the generated outside world (fixed ore nodes, rocks and nests; generating a location takes about a second per test). The ramp button needs a picked mission: `pick_mission(map)` picks the first one on offer (picking reinstances the location).

## Conventions

- Static typing everywhere (`var speed: float = 5.0`, typed function signatures).
- Follow the official GDScript style guide (snake_case files/functions, PascalCase classes/nodes).
- Gameplay logic separated from presentation where it helps testing (e.g. miner fill logic, resource inventory, upgrade math as plain testable classes/resources).
- Tunable values live in `Resource` files (`.tres`), not hardcoded (needed for playtest tuning anyway).
- Exported enums are saved as numbers in scenes and resources, so a new value goes at the end of its enum and nothing is renumbered or removed: `tests/project/test_saved_enums.gd` pins every exported enum's values in `tests/project/saved_enums.cfg` (a new value or enum goes there too).

## Cross-platform development

Development must work on Windows (Git Bash), Linux and macOS.

- Scripts are POSIX `sh`/`bash` (no PowerShell/`.bat`-only tooling); avoid GNU-only flags (e.g. `sed -i` differs on macOS) or use Python instead.
- No hardcoded absolute or machine-specific paths; use env vars (`GODOT4_EDITOR`, `BLENDER`, `BLENDER_MCP_PATH`) and paths relative to the repo root.
- Line endings are LF (`.gitattributes`); mark scripts executable in git with `git update-index --chmod=+x` (Windows doesn't keep the bit).
- File names: lowercase, no spaces, never rely on case to distinguish files (Windows/macOS file systems are case-insensitive).
- Platform-specific project settings use Godot feature overrides (e.g. `rendering_device/driver.windows`), never replace the shared default.

## MCP servers (`.mcp.json`)

- **godot-ai** ([hi-godot/godot-ai](https://github.com/hi-godot/godot-ai)), version pinned in `.mcp.json` (`godot-ai==<version>`); needs the editor plugin of the same version in `addons/godot_ai/` enabled and the editor open.
- **blender** (official Blender Lab MCP server), path supplied via the `BLENDER_MCP_PATH` env var so the repo stays machine-independent.
