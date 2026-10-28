# CI/CD (GitHub Actions)

| Workflow | Trigger | Steps |
|---|---|---|
| `ci.yml` | PR, merge queue, push to `main`, dispatch | gdformat check, gdlint, ruff, unit tests (headless Godot), import check |
| `godot-ai-plugin.yml` | push to `renovate/godot-ai` | commit the editor plugin matching `.mcp.json`, dispatch `ci.yml` (see Dependency updates) |
| `build.yml` | push to `main` | Export Windows + Linux (+ macOS later) builds, upload as workflow artifacts |
| `release.yml` (later, M8) | git tag `v*` | Export builds, create GitHub Release with zipped builds attached |
| `steam-deploy.yml` (later) | release / manual | Upload build to Steam via SteamCMD to a beta branch |

Godot is run headless in CI with matching export templates (version read from `.godot-version`).

`ci.yml` has the jobs `Lint GDScript` (`tools/lint.sh gdscript`), `Lint Python` (`tools/lint.sh python`) and `Test 1/8` to `Test 8/8` (a matrix, `tools/test.sh` with `TEST_SHARD`, each importing the project on its own runner), gathered by `Test`, which passes only when every share passed. `Lint GDScript`, `Lint Python` and `Test` are required status checks in the `main` ruleset, so a failing job blocks the merge; when changing the number of shares, change the matrix and `TEST_SHARD` together. The Godot binary and the Git LFS objects are cached between runs (LFS bandwidth quota): every run restores the newest LFS cache and pulls only what changed, but only `main` saves one (pruned to its checkout's objects first), since other branches can't use a pull request's cache and GitHub's 10 GB per repository would otherwise fill with them. The shared setup steps are composite actions in `.github/actions/` (`lfs-pull`, `setup-godot`), so workflows don't repeat them.

`build.yml` runs `tools/export.sh` (also usable locally): it imports the project, then exports a release build of every preset in `export_presets.cfg` to its export path under `builds/` (gitignored); CI uploads them as the `lodestorm-windows` / `lodestorm-linux` workflow artifacts. Presets: Windows Desktop and Linux, x86_64, PCK next to the binary, `tests/`, `addons/gut/`, `addons/godot_ai/` and `local/` excluded (the godot-ai plugin strips its own autoload from exports, so the game doesn't miss it). `application/modify_resources` (exe icon and metadata) is off because it needs rcedit, and Wine on Linux CI; turn it on with the release work (M8). `export_presets.cfg` is committed: Godot keeps signing credentials in `.godot/export_credentials.cfg`, never put them in the presets.

Export templates: the full archive is >1 GB, so `setup-godot` (with `export-templates: "true"`) downloads it once per Godot version and caches only the two release templates used. Locally, install them via the editor (Editor → Manage Export Templates), or extract `windows_release_x86_64.exe`, `linux_release.x86_64` and `version.txt` from the archive into Godot's `export_templates/<version>.stable/` folder in its user data directory (Windows `%APPDATA%\Godot`, Linux `~/.local/share/godot`, macOS `~/Library/Application Support/Godot`).

## Dependency updates (Renovate)

[Renovate](https://docs.renovatebot.com/) (config `.github/renovate.json5`) opens PRs early on Mondays; non-major updates are grouped into one PR. It tracks:

| Dependency | Source of truth | Note |
|---|---|---|
| GitHub Actions | `.github/workflows/*.yml`, `.github/actions/*/action.yml` | pinned to commit digests (`config:best-practices`) |
| gdtoolkit, ruff | `requirements-dev.txt` | |
| Godot | `.godot-version` | own PR (only `-stable` releases); open the project in the new editor so it updates `project.godot`, check GUT compatibility |
| godot-ai | `.mcp.json` | own PR (branch `renovate/godot-ai`); the `godot-ai-plugin.yml` workflow runs `tools/update-godot-ai.sh` there, commits the matching plugin in `addons/godot_ai/` and dispatches CI for that commit (pushes with `GITHUB_TOKEN` start no workflows). `tests/project/test_addon_versions.gd` fails until the versions match. The Mend-hosted Renovate app doesn't run our own commands as `postUpgradeTasks`, hence the workflow; Renovate ignores its commits (`gitIgnoredAuthors`) and keeps rebasing. By hand: `tools/update-godot-ai.sh` |

Vendored addons without a server counterpart (GUT) are updated by hand: GUT releases are tied to Godot versions.
