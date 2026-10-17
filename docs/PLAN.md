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
- Aliens damage the player (health, death and respawn exist since M1 for the storm)

## M3 — Ship hub

- Greybox ship interior with rooms
- Bigger outside world, generated per run from a seed and a biome (hills, plateaus and cliffs, plants and rocks, ore fields, nests); still greybox
- Spike: 3D menus (UI on a panel in the world, input via mouse, gamepad and later VR controllers, readability)
- Mission selection as a 3D menu at the bridge's holo table (pick from a few missions: location, timer, difficulty; the hologram previews the location, with the ore fields in their colors)
- Loadout selection before a mission (3D menu in the armory): pick a few of the owned weapons; first weapons besides the blaster: shotgun and hammer, switching between the loadout's weapons
- Ship states (space / landed + weather): start in space, land at the location when a mission is picked (loading it during the flight), take off into space once everyone is back aboard after the mission; the mission is confirmed at the holo table after previewing it
- Medical bay respawn
- Localization setup: English and German, all player-facing text through translations from the start (also the 3D menus and the text in the world)
- Upgrade station(s) spending resources (a few weapon/armor/miner upgrades): a console per upgrade room, MK1–MK3 paid from the hold, MK pips on the weapons and the helmet
- Save/load of persistent progress, saved automatically aboard (host: the ship's hold, later story, crew and quests; per player: weapons, loadout, upgrades, later skills; see [Co-op progression](GAME_DESIGN.md#co-op-progression)), one save with "Reset progress" at the settings terminal

## M4 — Progression & quests

- Spike: local AI voice-over (text to speech, offline, English) and subtitles as speech bubbles in the world, see [Localization and voice](GAME_DESIGN.md#localization-and-voice)
- More ore types: 14 in three bands (4 common, 4 mid, 6 signature ores, one per planet), each identifiable by color, crystal shape and glow pattern; biomes carry the common and mid ores, planets their signature ore; the cargo on the back as layered tubes, the wrist display with the cargo, the hold as tanks in the cargo bay (see [Resources](GAME_DESIGN.md#9-resources))
- Refinery: alloys from 2–3 ores, refining in real time
- Crafted miners (upgraded one by one, picked up again, lost when left behind or when everyone dies), standard-issue miners, drill types
- Risk vs. reward: nodes running dry, mining sites drawing aliens, rare ore far out and near nests, late deposits
- Ammo for ranged weapons (made from carried ore during a run, reloading with a timing press, magazine upgrades, refilling teammates' ammo), weapon MK upgrades, loadout slots for any weapon type
- Skills with the skill graph in the skills room: the first eight in four clusters (dash, reload on the move, reinforced suit, regeneration, spare magazines, careful reload, ore scanner, damage readout; see [Progression](GAME_DESIGN.md#12-progression--upgrades)); then the rescue drone, rebuilding spare magazines from ore, the miner radar and keeping part of the carried ore on death (sentries with co-op, M7)
- Quest framework: NPC quest givers, main and side quests tied to locations, quests that can't be missed, reputation, weapon blueprints as rewards (the shotgun first; until then only the debug overlay unlocks it)
- In-world menus instead of flat terminals (see [UI](GAME_DESIGN.md#ui-in-the-world-not-on-the-screen)): holo cards beside selectable parts, `tab_prev`/`tab_next`, a minimum text size and a test that every card fits in every language; the weapons rack and workbench, the armor fitting frame, the miners' maintenance pad, a locker per player in the armory; the bed to quit; the skill graph comes with the skills, the wrist display's quest log with the quest framework
- Navigator at the holo table (star system → planet, moon or station → region → landing site; the hologram no longer turns) and setting course at the cockpit's flight console; planets and moons with fixed regions (biome and set pieces), a new section generated per visit; stations as handcrafted maps without enemies
- First story pieces: one crew NPC with a quest chain, one expedition log; crew NPCs explain the mechanics so far (e.g. ammo and spare magazines at the armory)
- Station map: docking at a station (Waypost Ostra), a handcrafted map without enemies, with NPCs, a quest giver and maybe the ore exchange (see [Spaceship](GAME_DESIGN.md#5-spaceship-hub), Stations and outposts)

Order of the remaining work (each step builds on the ones before):

1. NPC template: a greybox crew figure with a name plate, talking to it as a station, speech bubbles, dialogue data with translation keys; first use: the quartermaster explains ammo, spare magazines and the timing reload
2. More ores (14, spread over biomes and planets)
3. Mission locations from map parts first (the 500 × 500 m field was a first iteration to walk on): a location put together from parts, with points of interest, corridors, open areas and the region's set pieces, so new biomes are built for it. Then the star system (decided, see [Missions](GAME_DESIGN.md#6-missions), Planets, moons and regions), in four PRs: **A** the world data (six planets with a gas giant, four moons, 25 regions, tiers, four new biomes as greybox); **B** the navigator as a campaign map (orbits compressed to fit the table, the ship's position and a route to the destination, a badge row with each region's ores, a name plate with tier and danger pips, locked bodies see-through with their signature ore as "?", each globe colored by its regions' biomes); **C** the four new biomes' ground texture sets (Blender); **D** opening planets with the engine room's upgrade, tier and storm scaling, and a pass over which ores the weapons, upgrades and skills cost, now that it's clear where each ore is found (the amounts stay **TBD (playtest)**)
4. More aliens (their own design round: how many, how kinds and roles combine, where they live) and the feel of combat: hit feedback, projectiles that tell the weapons apart, the basic alien fast enough to be a threat (and the blaster firing faster to match)
5. Station map: docking at Waypost Ostra, the handcrafted map, maybe the ore exchange
6. More crew: vendors at the ship's stations, the medic at the medical bay (health carries over between runs, players heal there before the next one, and the medic explains it), NPCs on the station who explain the mechanics (crew joining through the story waits for the quests)
7. More weapons (their own design round: in-game names for every weapon, like the ores and places; whether the blaster is the assault rifle). Until the quests hand out blueprints, the debug overlay unlocks them; their models come with the art pass
8. Refinery and crafted miners together, in one design round: miners are what alloys are first needed for (the refinery's space is reserved at the cargo bay's far end)
9. Destroyable nests
10. Quest framework and the wrist display's quest log, with the quartermaster's chain ending in the shotgun blueprint; quest steps that put blueprint fragments into a region's crates. Before it, a design round on the wrist display: with cargo, quests and quest items it gets crowded and hard to read

The rest (risk vs. reward, the voice spike, the remaining skills, the expedition log) fits in between where it helps.

## M5 — Art pass (Blender MCP)

- Models in the art direction ([`GAME_DESIGN.md`](GAME_DESIGN.md#art-direction)): player, miner (with a display for fill counter and time until full, placing and pickup animations, damage states), hose, ore nodes, aliens, ship exterior/interior, weapons
- Leftovers of the first models: dress the generated cliffs with the cliff chunks (`Cliff_*` in `assets/rocks/rocks.glb`) and the wall ore clusters (`Ore_<ore>_wall` in `assets/ores/<ore>.glb`), which needs placement along the cliff edges
- Leftovers of the player model: the death pose assumes flat ground (on slopes the body clips into the ground), the cargo canisters and other props on the player don't hide the occlusion silhouette behind them yet, no hit reaction or turn-in-place clips
- Leftovers of the swarmer: the body stays level on slopes (only the feet follow the ground), no hit reaction or turning clips, its death pose clips into slopes like the player's; raiders share its model (shaded darker) until they get their own strain; the brute and the spitter are still to model; the leg IK runs in GDScript (about 35 µs per alien and frame, 2.8 ms with 80 aliens), so profiling (M6) may move it to a cheaper path or skip it for aliens off screen
- Leftovers of the loadout: model the shotgun (with a shell per round in its strip, up to 12 with the magazine upgrade) and the hammer (greybox meshes so far) and give the hammer a swing animation (its head only sweeps sideways through the arc now; the player holds it in the rifle pose); a weapon rack in the armory that shows the owned weapons
- Basic VFX/SFX for mining, shooting, reloading (a cue for the timing window, also for VR and accessibility), storm

## M6 — VR

- OpenXR setup for Steam Frame
- Tabletop diorama camera rig
- VR controller mapping onto existing input actions
- 90 FPS profiling

## M7 — Co-op

- Godot high-level multiplayer (host + up to 3 clients), drop-in: friends join a player's session any time, no separate solo mode
- Comms station on the bridge: invites through the platform (Steam overlay), and the comms log (radio lines to listen to again)
- Sync players, miners, aliens, resources
- Shared ship hub
- Co-op progression: host save plus each player's own gear, tier sync (see [Co-op progression](GAME_DESIGN.md#co-op-progression))

## M8 — Platform services & release

- `PlatformService` abstraction + GodotSteam backend
- Achievements (in-game list + Steam)
- `release.yml` (GitHub Releases on tag) and `steam-deploy.yml`
- Steam store page / Early Access preparation (see [`TECHNICAL.md`](TECHNICAL.md#steam-publishing--first-timer-checklist))

## Afterwards

Epic / GOG ports. Iterate based on playtesting: more planets, alien types, miner types/defenses, mission objectives, NPC/story content.

Not placed in a milestone yet (see [`GAME_DESIGN.md`](GAME_DESIGN.md)): the full story campaign and crew, more stations and the outposts, voice-over for all lines, the radio comms log, more languages, AI-driven NPCs (experiment).
