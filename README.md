# Lodestorm

A 3D isometric mining/action game with a dark, realistic sci-fi look. You live on a spaceship that serves as your hub: pick a mission, land, place miners on resource nodes, fight off aliens, haul the ore back, and get back on board before the storm hits. Spend what you mined on upgrades, then go again.

> **Status: pre-production.** Milestone 4 (progression & quests) in progress. The full loop of missions, mining, aliens, weapons, the ship hub, the refinery, upgrades and skills is playable, mostly in greybox; the first art is in (the ship's interior, the people with their voices in English and German). Quests, the rest of the art pass, VR and co-op come later (see the [plan](docs/PLAN.md)).

## Tech

- **Engine:** [Godot](https://godotengine.org/) (version in [`.godot-version`](.godot-version)), GDScript (statically typed), Forward+ renderer (Vulkan), Jolt Physics.
- **Platforms:** desktop first (Windows, Linux, macOS later); VR (Steam Frame via OpenXR) as a second mode.
- **Players:** solo, with optional co-op for up to 4 players.
- **Assets:** made in Blender, exported as `.glb`; binary files are stored with Git LFS.

## AI use

Lodestorm is designed, directed and reviewed by [Shinigami92](https://github.com/Shinigami92), but the code, assets and docs are largely made with AI. The generated assets in the game are first tries: they already look better than greybox, and they'll be changed and improved in later iterations. The models that make the assets run locally, their licenses allow a commercial release, and no real person's voice or likeness is cloned.

| AI | What | How |
|---|---|---|
| [Claude Code](https://claude.com/claude-code) | Code, docs, tests, tools; the build scripts of the procedural models (most aliens, weapons, the ship) and the synthesized sound effects | written with AI, reviewed by hand |
| [Z-Image Turbo](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo) (Apache-2.0) | Concept images, the boot screen's emblem | rated by hand; the concepts are the references for the models |
| [TRELLIS.2](https://github.com/microsoft/TRELLIS.2) (MIT), with [BiRefNet](https://github.com/ZhengPeng7/BiRefNet) (MIT) | 3D models: the player's suit, the swarmer, the people's outfits, hair and heads | made from a concept image, then fitted and rigged by build scripts; the people's bodies are [MakeHuman](https://static.makehumancommunity.org/) (CC0) |
| [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS) (Apache-2.0) | Voices of Brannik, Nell, Kade, Selin and the crew (English and German) | each voice designed from a written description of the character, every line cloned from that voice |

What made each asset is recorded next to it (see [Asset pipeline](docs/technical/assets.md)).

## Playing it

Open the project in the Godot editor (see [Setup](CONTRIBUTING.md#setup)) and press F5. Keyboard and mouse or a gamepad:

| Action | Keyboard / mouse |
|---|---|
| Move / aim | WASD / mouse (gamepad: left / right stick) |
| Attack | left mouse button |
| Talk, use, pick up | E |
| Place a miner | F |
| Reload (press again in the window for a timing reload) | R |
| Switch weapon | Q |
| Dash | Space |
| Zoom | mouse wheel |
| Pause | Esc |
| Debug overlay (tuning, debug actions) | F3 |

## Documentation

- [Game design](docs/design/README.md): the game as it is built, its vision and rules, one file per topic
- [Planned designs](docs/planned/README.md): decided, not built yet, one file per topic
- [Development plan / milestones](docs/PLAN.md): what's done and what's next
- [Technical guidelines](docs/technical/README.md): licensing, code conventions and architecture, CI, the asset pipeline (models, sounds, voices), platform services, one file per topic

## Contributing

Bug reports, ideas and pull requests are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for setup, workflow and the CLA.

## License

Copyright (c) 2026 Christopher Quadflieg (Shinigami92).

This project's own code and assets are licensed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) (see [`LICENSE`](LICENSE)): you may share and adapt them with attribution, for non-commercial purposes, under the same license. This makes the project *source-available*, not OSI open source; the commercial release of the game is reserved to the author.

Third-party code and assets keep their own licenses, included next to them (e.g. [`addons/godot_ai/`](addons/godot_ai/LICENSE) and [`addons/gut/`](addons/gut/LICENSE.md), MIT).

Contributions require signing a Contributor License Agreement (CLA), see [`CONTRIBUTING.md`](CONTRIBUTING.md#contributor-license-agreement-cla).
