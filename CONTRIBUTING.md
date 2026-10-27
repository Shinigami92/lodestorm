# Contributing to Lodestorm

Thanks for your interest! This guide covers how to set up the project and how changes get in. The technical rules themselves live in [`docs/TECHNICAL.md`](docs/TECHNICAL.md); this file links there instead of repeating them.

## Requirements

- [Godot](https://godotengine.org/download), the exact version from [`.godot-version`](.godot-version) (standard build, not .NET)
- [Git](https://git-scm.com/) with [Git LFS](https://git-lfs.com/)
- On Windows: Git Bash (all scripts are POSIX shell; Windows, Linux and macOS are all supported for development)
- [Python](https://www.python.org/) 3 for the formatters/linters, pinned in [`requirements-dev.txt`](requirements-dev.txt): [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit) for GDScript, [ruff](https://docs.astral.sh/ruff/) for the Python asset scripts
- Optional, for AI-assisted development with [Claude Code](https://claude.com/claude-code):
  - [uv](https://docs.astral.sh/uv/) (runs the MCP servers in [`.mcp.json`](.mcp.json))
  - [Blender](https://www.blender.org/download/) with the [Blender Lab MCP add-on](https://www.blender.org/lab/mcp-server/)

## Setup

```sh
git lfs install
git clone https://github.com/Shinigami92/lodestorm.git
```

Then open the folder (`project.godot`) in the Godot editor. The first start imports all assets, which takes a moment.

Install the dev tools, ideally in a virtual environment (`.venv/` is gitignored):

```sh
python -m venv .venv
. .venv/bin/activate        # Windows (Git Bash): . .venv/Scripts/activate
pip install -r requirements-dev.txt
```

Run the same checks as CI before opening a pull request:

```sh
tools/lint.sh   # gdformat --check + gdlint, ruff format --check + ruff check (only one: gdscript | python)
tools/test.sh   # GUT unit tests, headless (needs GODOT4_EDITOR)
```

On a fresh checkout, `tools/import.sh` imports the project headless first (the tests need the import cache). After writing or patching `.tscn`/`.tres` files outside the editor, run `tools/uids.sh` (a test checks every reference has its UID).

`tools/export.sh` builds the Windows and Linux release exports into `builds/` (needs the export templates, see [CI/CD](docs/TECHNICAL.md#3-cicd-github-actions)).

Machine-specific paths live in environment variables, never in the repo:

| Variable | Used by | Example |
|---|---|---|
| `GODOT4_EDITOR` | command-line scripts, VS Code [godot-tools](https://marketplace.visualstudio.com/items?itemName=geequlim.godot-tools) (`.vscode/settings.json`) | `E:\Godot\Godot_v<version>-stable_win64.exe` |
| `BLENDER` | `tools/blender.sh` (asset build scripts, headless) | path to the Blender executable |
| `BLENDER_MCP_PATH` | Blender MCP server (`.mcp.json`) | path to the `mcp/` folder of a [blender_mcp](https://projects.blender.org/lab/blender_mcp) clone |

The asset tools for concept images, image-to-3D models and voice lines have their own variables, listed with them in [Asset pipeline](docs/TECHNICAL.md#4-asset-pipeline); the MCP servers' setup is in [MCP servers](docs/TECHNICAL.md#mcp-servers-mcpjson).

## Workflow

1. **Open an issue first** for anything bigger than a small fix, so we can agree on the approach before you spend time on it. Design changes should fit [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md), the designs already decided in [`docs/planned/`](docs/planned/README.md) and the current milestone in [`docs/PLAN.md`](docs/PLAN.md).
2. **Fork and branch** from `main`; keep one topic per branch. `main` is protected: every change goes through a pull request.
3. **Keep pull requests small** and focused. Describe what changed and why, and how you tested it (desktop, gamepad, VR if relevant).
4. **CI must pass** (formatting, linting, tests, import check); failing jobs block the merge. There are no git hooks, run `tools/lint.sh` and `tools/test.sh` yourself.
5. If your change affects a documented decision, **update the docs** in the same pull request: a decided design goes into [`docs/planned/`](docs/planned/README.md); once it's built, its part moves into [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) (describing what was built) and its line in [`docs/PLAN.md`](docs/PLAN.md) moves to Done.
6. Pull requests are **squash-merged**, and the **pull request title becomes the commit message** on `main`, so the title must follow the [commit message](#commit-messages) format. Commits inside your branch can be anything.

## Code and assets

- **GDScript:** statically typed everywhere, following the official style guide; code must pass `gdformat --check` and `gdlint`. Details: [Code quality](docs/TECHNICAL.md#2-code-quality).
- **Python** (Blender asset scripts): must pass `ruff format --check` and `ruff check` (config in `ruff.toml`).
- **Cross-platform:** no machine-specific paths, POSIX shell scripts, LF line endings, lowercase file names. Details: [Cross-platform development](docs/TECHNICAL.md#cross-platform-development).
- **Versions** are defined once and referenced (Godot: `.godot-version`); don't hardcode them elsewhere.
- **Tunable gameplay values** go into `Resource` files (`.tres`), not into code.
- **Player-facing text** is written in English and goes through translations (`tr()` in scripts); after adding or changing texts, run `tools/translations.sh` and add the German translation in `locale/de.po`. New languages and translation fixes are welcome as pull requests. Details: [Localization](docs/TECHNICAL.md#localization).
- **Assets:** Blender source files (`.blend`) are committed next to the exported `.glb`; binary files are tracked with Git LFS automatically via [`.gitattributes`](.gitattributes). Details: [Asset pipeline](docs/TECHNICAL.md#4-asset-pipeline).
- **Third-party material** (addons, models, textures, sounds, fonts) is only accepted with a license that allows redistribution in this repo and in the commercial release. Keep its license file next to it and mention the source in the pull request.

## Commit messages

One [Conventional Commits](https://www.conventionalcommits.org/) title under 64 characters, no body. This applies to pull request titles (they become the squash commit) and to direct commits. For example:

```text
feat: add miner fill indicator
fix: stop hose transfer when out of range
docs: describe storm damage
```

## Contributor License Agreement (CLA)

Lodestorm is source-available under [CC BY-NC-SA 4.0](LICENSE), but the game itself will be sold (Steam and other stores). To include your contribution in the commercial release, you must sign the [CLA](CLA.md) once before your first pull request can be merged. A bot ([CLA Bot](https://cla.fiveonefour.com/)) asks you to do so on your pull request; signing takes a minute in the browser (sign in with GitHub, read, confirm) and covers all your later contributions. Afterwards the check on your pull request turns green by itself; if it doesn't, comment `/recheck`.

In short: you keep the copyright to your contribution and grant the maintainer a license to use it in the project, including the commercial release, under any license. You confirm that the contribution is yours (or third-party material you name with its license) and that any AI tools used to make it are named in the pull request. The [CLA](CLA.md) itself is what counts.

## Questions

Ask in [GitHub Discussions](https://github.com/Shinigami92/lodestorm/discussions); use [issues](https://github.com/Shinigami92/lodestorm/issues) for bugs and concrete proposals.
