# Lodestorm — Technical Guidelines

## 1. Source-available & licensing

- Code **and** assets (incl. `.blend` source files) are public on GitHub.
- License: **[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)** for everything original to this project (full text in `LICENSE`).
  - Others may fork, modify and share, with attribution, non-commercially, under the same license.
  - Only the owner sells the game (Steam/Epic/GOG). Strictly speaking this is *source-available*, not OSI "open source".
  - Third-party code and assets keep their own licenses, shipped next to them (e.g. `addons/godot_ai/` and `addons/gut/` are MIT, see their license files; GUT's bundled fonts are OFL). Only add third-party material whose license allows redistribution in this repo and in the commercial release.
- **CLA required for contributions** (via [CLA Assistant](https://github.com/cla-assistant/cla-assistant) GitHub app), so the owner may use contributions in the commercial release.
- Game name/logo: consider protecting as trademark before release.
- Get a short legal review before the commercial release.
- Secrets (Steam credentials, store tokens) only live in GitHub Actions secrets, never in the repo.

## 2. Code quality

| Tool | Purpose |
|---|---|
| [godot-gdscript-toolkit](https://github.com/Scony/godot-gdscript-toolkit) `gdlint` | Linting (naming, complexity, ordering) — config in `gdlintrc` (only overrides of the defaults) |
| `gdformat` (same toolkit) | Formatting, checked with `gdformat --check` — config in `gdformatrc` |
| Godot GDScript warnings | Enforce static typing: `untyped_declaration`, `unsafe_property_access`, `unsafe_method_access`, `unsafe_call_argument` are **errors** in the project settings, so a violating script fails to load. `addons/` is exempt (Godot's default `directory_rules`) |
| Unit tests | [GUT](https://github.com/bitwes/Gut) in `addons/gut/` (version in its `plugin.cfg`, must support the pinned Godot version), tests in `tests/` (`test_*.gd`, config `.gutconfig.json`), run headless |
| `.editorconfig` | Consistent whitespace/line endings across editors |

All checks are enforced by CI on every pull request (failing jobs block the merge), not by local git hooks. The same scripts run locally and in CI:

- `tools/lint.sh` — `gdformat --check` + `gdlint` over the project (`addons/`, `local/`, `tmp/` excluded in the rc files). gdtoolkit is pinned in `requirements-dev.txt`: `pip install -r requirements-dev.txt`, ideally in a `.venv/` (gitignored).
- `tools/test.sh` — imports the project (fails if the import prints any `ERROR`, e.g. an LFS pointer instead of a file), then runs GUT headless with `$GODOT4_EDITOR`; extra arguments go to GUT (e.g. `-gselect=test_foo.gd`). Exits non-zero on failures.
- GUT silently skips test scripts that fail to parse, so `tests/test_scripts_parse.gd` loads every project script and fails on parse or typing errors.

`scripts/` holds game GDScript; developer shell scripts live in `tools/` (ignored by Godot via `.gdignore`).

### Conventions

- Static typing everywhere (`var speed: float = 5.0`, typed function signatures).
- Follow the official GDScript style guide (snake_case files/functions, PascalCase classes/nodes).
- Gameplay logic separated from presentation where it helps testing (e.g. miner fill logic, resource inventory, upgrade math as plain testable classes/resources).
- Tunable values live in `Resource` files (`.tres`), not hardcoded — needed for playtest tuning anyway.

### Cross-platform development

Development must work on Windows (Git Bash), Linux and macOS.

- Scripts are POSIX `sh`/`bash` (no PowerShell/`.bat`-only tooling); avoid GNU-only flags (e.g. `sed -i` differs on macOS) or use Python instead.
- No hardcoded absolute or machine-specific paths; use env vars (`GODOT4_EDITOR`, `BLENDER_MCP_PATH`) and paths relative to the repo root.
- Line endings are LF (`.gitattributes`); mark scripts executable in git with `git update-index --chmod=+x` (Windows doesn't keep the bit).
- File names: lowercase, no spaces, never rely on case to distinguish files (Windows/macOS file systems are case-insensitive).
- Platform-specific project settings use Godot feature overrides (e.g. `rendering_device/driver.windows`), never replace the shared default.

### Engine settings

- **Versions:** each version is defined once and referenced everywhere else. Godot: `.godot-version` (read by CI and scripts; when upgrading, also let the editor update `config/features` in `project.godot`). godot-ai: `.mcp.json`, kept equal to `addons/godot_ai/plugin.cfg`.
- Renderer Forward+, Jolt physics, **Vulkan on all platforms** (Godot's default, so `project.godot` has no driver line). D3D12 was rejected: in a sibling project on the same Godot 4.7.2 + SteamVR setup it logged texture errors every frame and the headset image stayed black, while Vulkan worked. Retry D3D12 only after a Godot update and with a reason.

### MCP servers (`.mcp.json`)

- **godot-ai** ([hi-godot/godot-ai](https://github.com/hi-godot/godot-ai)), version pinned in `.mcp.json` (`godot-ai==<version>`); needs the editor plugin of the same version in `addons/godot_ai/` enabled and the editor open.
- **blender** (official Blender Lab MCP server), path supplied via the `BLENDER_MCP_PATH` env var so the repo stays machine-independent.

## 3. CI/CD (GitHub Actions)

| Workflow | Trigger | Steps |
|---|---|---|
| `ci.yml` | every push / PR | gdformat check, gdlint, unit tests (headless Godot), import check |
| `build.yml` | push to `main` | Export Windows + Linux (+ macOS later) builds, upload as workflow artifacts |
| `release.yml` | git tag `v*` | Export builds, create GitHub Release with zipped builds attached |
| `steam-deploy.yml` (later) | release / manual | Upload build to Steam via SteamCMD to a beta branch |

Godot is run headless in CI with matching export templates (version read from `.godot-version`).

`ci.yml` has two jobs, `Lint` (`tools/lint.sh`) and `Test` (`tools/test.sh`); both are required status checks in the `main` ruleset, so a failing job blocks the merge. The Godot binary and the Git LFS objects are cached between runs (LFS bandwidth quota).

## 4. Asset pipeline

- Blender (via Blender MCP) → export glTF (`.glb`) → `assets/` in Godot.
- `.blend` source files are committed too (open source).
- Binary assets (`.blend`, textures, audio) via **Git LFS** (watch GitHub LFS storage/bandwidth quotas).

## 5. Platform services & distribution

### Abstraction

A `PlatformService` layer (autoload) with backends:

- `NullPlatform` — GitHub/itch builds, development, CI (no-op)
- `SteamPlatform` — via [GodotSteam](https://godotsteam.com/) (GDExtension)
- `EpicPlatform` / `GogPlatform` — later, via EOS / GOG Galaxy plugins (to be evaluated)

Gameplay only calls e.g. `PlatformService.unlock_achievement(&"first_miner")`; the game must run fully without any store client.

### Achievements

- Defined once in the game (id, name, description, icon), mirrored in each store's backend config.
- Optional in-game achievement list so non-Steam builds have them too.
- During development Steam's test App ID `480` (Spacewar) is used until the real App ID exists.

### Steam publishing — first-timer checklist

1. Create a Steamworks partner account (identity, tax and bank info).
2. Pay the Steam Direct fee per game (currently USD 100, recoupable after USD 1,000 gross revenue). After payment there is a mandatory waiting period (~30 days) before release.
3. Get the App ID; set up depots (Windows/Linux/macOS), and the SteamPipe upload via SteamCMD.
4. Configure achievements + icons in Steamworks.
5. Build the store page (capsule images, screenshots, trailer, description) → Valve review.
6. "Coming Soon" page must be public for at least ~2 weeks before release (wishlists matter a lot).
7. Upload a build → Valve build review → release (Early Access is an option for an iterating game).

These rules may change; re-verify on the Steamworks documentation when we get there.

### Other stores

Epic Games Store and GOG have their own submission processes and SDKs — evaluated once the game approaches release.
