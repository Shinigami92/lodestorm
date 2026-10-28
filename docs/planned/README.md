# Planned designs

Designs that are decided but not built yet, one file per topic. [`design/`](../design/README.md) describes the game as it is built (with its vision and rules); these files describe what changes next. [`PLAN.md`](../PLAN.md) lists the work in order, with a link to each file.

- A file is the result of a design round: what was decided, with starting values marked **TBD (playtest)**. The pull requests that build it are listed in `PLAN.md`, not here.
- When a part is built, its text moves into the matching file in [`design/`](../design/README.md) (rewritten to describe what was built) and leaves this file; once nothing is left, the file is deleted.
- A file here names things that don't exist yet; `design/` describes what does and only points here for what's coming ("Planned: ... see `planned/...`").

| File | What's left | Milestone |
|---|---|---|
| [`player-display.md`](player-display.md) | what's left of the suit ring: the quest's pointer, the player color, VR | M4 (step 16), M6, M7 |
| [`menu-pause.md`](menu-pause.md) | what's left of the title view and the pause panel: co-op sessions, the Steam overlay, more settings, VR | M6, M7, M8 |
| [`biomes.md`](biomes.md) | around the biomes' geography: weather, a generic part per biome, the biomes' assets | M5 |
| [`aliens.md`](aliens.md) | the Ravager guarding rich sites, more guards and raiders, co-op scaling, the effects | M4 (steps 14, 16), M5, M7 |
| [`sfx.md`](sfx.md) | recordings where synthesis isn't enough, the menus' and the death's sounds later, the sounds still to come | M5 |
| [`weapons.md`](weapons.md) | blueprints from the quests and their order, a third slot, projectiles, co-op and VR | M4 (step 16), M5, M6, M7 |
| [`refinery.md`](refinery.md) | the station's alloy requests, furnaces through the quests, the engineer, later drill heads, the art pass | M4 (step 16), M5 |
| [`station.md`](station.md) | Waypost Ostra: why players go there, requests instead of shops, more seats, co-op, its look | M4 (step 16), M5, M7 |
| [`crew.md`](crew.md) | the crew joining, more transmissions, co-op | M4 (step 16), M7 |
| [`npc-places.md`](npc-places.md) | the bar's closing time, starting along their day, smarter NPCs | later |
| [`people.md`](people.md) | the colonists' models, props, faces, fighting people, the player's suit | M5 |
| [`skills.md`](skills.md) | where the skill graph is heading | M7, later |
| [`quests.md`](quests.md) | quests as data, goals, the quest board, requests, the story's acts, first content | M4 (step 16) |
| [`story.md`](story.md) | the flare shield, the six acts, the expedition (Calder, Pell), the people's threads, after the ending | M4 (step 16 D and on) |
| [`characters.md`](characters.md) | the named people's sheets for the writing rounds: background, wants, flaw, secret, arc, ties, voice; the crew's founding, the ship's past, who joins in act 1 | M4 (step 16 D and on) |
| [`world.md`](world.md) | the frame for the writing rounds: the timeline, travel and the lane, the charter, the hive's origin, daily life, the colony's numbers, the smaller stations and traffic | M4 (step 16 D and on) |
| [`coop-ore.md`](coop-ore.md) | ship and quest costs taken from the haul, the cargo hatch showing what they took | M4 (step 16), M7 |
| [`voice.md`](voice.md) | the rest of the cast, the radio later, Fenna's voice, strained anchors | M5, M7 |
| [`ship-exterior.md`](ship-exterior.md) | the ship's outside: detail and textures, effects | M5 |
| [`ship-interior.md`](ship-interior.md) | what's left inside the ship: the specimen lab's tanks, room beside the holo table, reserved spaces, wall bays, key objects, ceilings | M5 |
| [`art.md`](art.md) | each body's light, how dark, the storm's light, four player colors with numbers | M5, M7 |
| [`vr-view.md`](vr-view.md) | the VR head on the desktop camera's line, the haze, the sky per body, the land beyond the map | M5 (sky, far ring), M6 |
| [`coop-revive.md`](coop-revive.md) | going down before dying in co-op, reviving by standing close, respawning after 30 s | M7 |
| [`stats.md`](stats.md) | the statistics' live `/metrics` endpoint for Prometheus, the statistics station aboard | M4 (alongside), M8 |
