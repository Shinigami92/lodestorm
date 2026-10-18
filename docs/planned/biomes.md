# Biome geography (planned)

Decided 2026-10-17, built in M4 step 6 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. The framework is built (step 6 A): a biome's barrier (walls, gaps, or gaps with the rock behind them), its passes (winding, bridges or slot canyons; ramps between terraces), its own kinds of areas and its hazard are data on `LocationBiome`. The *Frost fields* (step 6 A), *Salt pans* and *Ash fields* (step 6 B), *Dust flats* and *Glass plains* (step 6 C) use it (see [Generated outside world](../GAME_DESIGN.md#6-missions)). The *Overgrowth* still has walls and winding passes, with its own numbers, scatter and tint.

## The Overgrowth

It picks a barrier, a pass style, its two area kinds and its hazard; the new ones (growth walls, trails, mud) are added to the framework. Its fungal grove's stalks can grow only there like the shard gardens' spires (`ScatterType.area_kinds`).

| Biome | Barrier | Passes | Own area kinds | Hazard | Plays like |
|---|---|---|---|---|---|
| *Overgrowth* | low walls plus **growth walls** (giant fungal stalks and roots that block walking and shots, low on the camera's side like the rock) | **trails** through the growth, many loops | **mire** (shallow mud pools), **fungal grove** (stalks as cover, short sightlines) | **mud** slows players and aliens (to about 60 %) | a maze, ambushes |

- Hazards stay mild, readable and avoidable, never instant death, never in the landing yard or on a pass's lane; they slow or hurt aliens too.

## Around it

- **Biomes and aliens:** the strains' biome leanings (see [`aliens.md`](aliens.md)) fit the barriers: burrowers on the open ground of the Dust flats and Salt pans, stalkers in the Overgrowth's cover, darters over the gaps and terraces of the Frost fields, Ash fields and Glass plains. Gaps make aliens walk around to the next bridge, which slows them.
- **Weather per biome** (art pass): particles and fog, cheap enough for VR: drifting sand, spores and mist in the hollows, snow flurries, heat shimmer, falling ash and the lava's glow, glare off the glass. The storm takes over at the end; the light stays muted so ores and aliens stand out.
- **Map parts in every biome:** the generic parts and the set pieces stay biome-neutral, re-dressed with the biome's materials later (a wreck in ice, a wreck in glass); each biome gets one generic part of its own with the assets (e.g. a frozen-in drill rig, a salt-crusted pump station).
- **Region sizes** stay as they are: the open biomes cover more ground with the same number of areas and keep their timers, the long sightlines make up for the walk (check in playtests).
- **Assets** (Blender, heavy on the GPU, with the art pass in M5, after the layouts work in greybox): per biome a ground texture set (floor, barrier, the barrier's lip), its scatter (5–8 rocks and plants) and its feature meshes (snow bridge, crust crossing, shard spikes, fungal stalks, lava).
