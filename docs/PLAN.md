# Lodestorm — Development Plan

Goal: reach a playable, fun core loop as early as possible with greybox visuals, then layer hub, art, VR and co-op on top. Each milestone ends with something playable.

## M0 — Project setup

- Git repo + Godot `.gitignore`, `.gitattributes` (LFS), `.editorconfig`, LICENSE (CC BY-NC-SA 4.0), CONTRIBUTING + CLA, README
- Godot project (version pinned in `.godot-version`), folder structure (`scenes/`, `scripts/`, `assets/`, `docs/`, `tests/`)
- gdtoolkit (`gdlint`, `gdformat`) config, enforced by CI (no local git hooks)
- Static typing warnings enabled in project settings
- Unit test framework + one example test
- GitHub Actions: `ci.yml` (format, lint, tests) and `build.yml` (Windows/Linux export artifacts)
- Renovate for dependency updates
- Input map: keyboard/mouse + gamepad actions (move, aim, attack, interact, ...)
- Rendering settings with performance targets in mind (Forward+ desktop, check Mobile/compatible path for VR later)

## M1 — Outside loop (greybox) ⭐ core fun test

- One small test map with resource nodes (2–3 ore types)
- Player: movement, aiming (mouse + right stick), shooting (one ranged weapon; weapon base class ready for more, incl. melee)
- Isometric camera
- Place miners on nodes; miners fill over time and stop when full
- Hose: auto-connect within radius, visible line, transfer while moving
- Big greybox ship with the ramp on the right, lowered by a button inside: the mission (and its timer) starts when the first player steps out and ends when everyone is back aboard; the ramp goes up, and the button starts the next run in a fresh outside world
- Timer expiry → storm damage
- Win (return in time → resources kept) / lose (death → resources lost)
- Player feedback in the world, no 2D HUD (see [UI](GAME_DESIGN.md#ui-in-the-world-not-on-the-screen)): miner fill level, carried resources, timer / storm
- Debug overlay for tuning values (fill rate, transfer speed, timer); 2D is fine here, developer tool only

## M2 — Aliens

- Basic alien(s): chase + attack player
- Spawner with escalation over time
- Aliens optionally targeting miners
- Player health, damage, death

## M3 — Ship hub

- Greybox ship interior with rooms
- Spike: 3D menus (UI on a panel in the world, input via mouse, gamepad and later VR controllers, readability)
- Mission terminal as a 3D menu (pick from a few missions: location, timer, difficulty)
- Loadout selection before a mission (3D menu): pick a few of the owned weapons
- Ship states (space / landed + weather) and ramp → starts mission
- Medical bay respawn
- Upgrade station(s) spending resources (a few weapon/armor/miner upgrades)
- Save/load of persistent progress

## M4 — Art pass (Blender MCP)

- Stylized models: player, miner (with a display for fill counter and time until full), hose, ore nodes, aliens, ship exterior/interior, weapons
- Basic VFX/SFX for mining, shooting, storm

## M5 — VR

- OpenXR setup for Steam Frame
- Tabletop diorama camera rig
- VR controller mapping onto existing input actions
- 90 FPS profiling

## M6 — Co-op

- Godot high-level multiplayer (host + up to 3 clients)
- Sync players, miners, aliens, resources
- Shared ship hub

## M7 — Platform services & release

- `PlatformService` abstraction + GodotSteam backend
- Achievements (in-game list + Steam)
- `release.yml` (GitHub Releases on tag) and `steam-deploy.yml`
- Steam store page / Early Access preparation (see [`TECHNICAL.md`](TECHNICAL.md#steam-publishing--first-timer-checklist))

## Afterwards

Epic / GOG ports. Iterate based on playtesting: more planets, alien types, miner types/defenses, mission objectives, NPC/story content.
