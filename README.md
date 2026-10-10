# Lodestorm

A stylized 3D isometric mining/action game. You live on a spaceship that serves as your hub: pick a mission, land, place miners on resource nodes, fight off aliens, haul the ore back, and get back on board before the storm hits. Spend what you mined on upgrades, then go again.

> **Status: pre-production.** Milestone 1 (greybox outside loop) in progress: a test map where you can walk around and aim.

## Tech

- **Engine:** [Godot](https://godotengine.org/) (version in [`.godot-version`](.godot-version)), GDScript (statically typed), Forward+ renderer (Vulkan), Jolt Physics.
- **Platforms:** desktop first (Windows, Linux, macOS later); VR (Steam Frame via OpenXR) as a second mode.
- **Players:** solo, with optional co-op for up to 4 players.
- **Assets:** made in Blender, exported as `.glb`; binary files are stored with Git LFS.

> **AI disclaimer:** Lodestorm is designed, directed and reviewed by [Shinigami92](https://github.com/Shinigami92), but the code, assets and docs are largely written with AI, using [Claude Code](https://claude.com/claude-code).

## Documentation

- [Game design](docs/GAME_DESIGN.md)
- [Development plan / milestones](docs/PLAN.md)
- [Technical guidelines](docs/TECHNICAL.md): tooling, CI, licensing, platform services

## Contributing

Bug reports, ideas and pull requests are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for setup, workflow and the CLA.

## License

Copyright (c) 2026 Christopher Quadflieg (Shinigami92).

This project's own code and assets are licensed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) (see [`LICENSE`](LICENSE)): you may share and adapt them with attribution, for non-commercial purposes, under the same license. This makes the project *source-available*, not OSI open source; the commercial release of the game is reserved to the author.

Third-party code and assets keep their own licenses, included next to them (e.g. [`addons/godot_ai/`](addons/godot_ai/LICENSE) and [`addons/gut/`](addons/gut/LICENSE.md), MIT).

Contributions require signing a Contributor License Agreement (CLA), see [`CONTRIBUTING.md`](CONTRIBUTING.md#contributor-license-agreement-cla).
