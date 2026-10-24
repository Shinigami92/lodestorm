# Planned designs

Designs that are decided but not built yet, one file per topic. [`GAME_DESIGN.md`](../GAME_DESIGN.md) describes the game as it is built (with its vision and rules); these files describe what changes next. [`PLAN.md`](../PLAN.md) lists the work in order, with a link to each file.

- A file is the result of a design round: what was decided, with starting values marked **TBD (playtest)**. The pull requests that build it are listed in `PLAN.md`, not here.
- When a part is built, its text moves into `GAME_DESIGN.md` (rewritten to describe what was built) and leaves this file; once nothing is left, the file is deleted.
- A file here names things that don't exist yet; `GAME_DESIGN.md` describes what does and only points here for what's coming ("Planned: ... see `planned/...`").

| File | What | In `PLAN.md` |
|---|---|---|
| [`player-display.md`](player-display.md) | the suit ring on the ground | with the weapons, crafted miners and quests (M4) |
| [`menu-pause.md`](menu-pause.md) | what's left of the title view and the pause panel: co-op sessions, the Steam overlay, more settings, VR | M6, M7, M8 |
| [`biomes.md`](biomes.md) | around the biomes' geography: the aliens' leanings, weather, a generic part per biome, the biomes' assets | M4, step 7 B (leanings), M5 |
| [`aliens.md`](aliens.md) | eleven strains and the Ravager, roles, armor and stagger, hatch tables, hit feedback | M4, steps 7, 9 A |
| [`sfx.md`](sfx.md) | recordings where synthesis isn't enough, the menus' and the death's sounds later, the sounds still to come | later rounds, the art pass (M5) |
| [`weapons.md`](weapons.md) | 18 weapons with names, feeds, upgrade parts, the armory's weapon wall | M4, step 10 |
| [`refinery.md`](refinery.md) | the station's alloy requests, furnaces through the quests, the engineer, later drill heads, the art pass | M4 steps 12–16, M5 |
| [`station.md`](station.md) | Waypost Ostra: the ore exchange, its NPCs (docking and the map are built) | M4, step 12 |
| [`crew.md`](crew.md) | the crew joining, reactions to events, the pilot on the radio | M4, step 13 |
| [`risk-reward.md`](risk-reward.md) | rich ore by the nests, the late meteor, banking ore at a cargo hatch | M4, step 14 |
| [`skills.md`](skills.md) | the rescue drone, the hardened canister, rebuilding spares, the miner radar; where the skill graph is heading | M4, step 15 |
| [`quests.md`](quests.md) | quests as data, goals, the quest board, requests, the story's acts, first content | M4, step 16 |
| [`story.md`](story.md) | the flare shield, the six acts, the expedition (Calder, Pell), the people's threads, after the ending | M4, step 16 D and on |
| [`coop-ore.md`](coop-ore.md) | every player's own hold, the whole haul for everyone, ship and quest costs taken from the haul | M4, steps 4, 11, 16; M7 |
| [`voice.md`](voice.md) | the voice-over spike, voices without cloning real people, the pipeline, playback and the radio filter | M5, after the models |
| [`art.md`](art.md) | each body's light, how dark, the storm's light, four player colors with numbers | M5, M7 |
| [`vr-view.md`](vr-view.md) | the VR head on the desktop camera's line, the haze, the sky per body, the land beyond the map | M5 (sky, far ring), M6 |
| [`coop-revive.md`](coop-revive.md) | going down before dying in co-op, reviving by standing close, respawning after 30 s | M7 |
| [`stats.md`](stats.md) | the statistics' live `/metrics` endpoint for Prometheus, the statistics station aboard | M4 (alongside), M8 |
