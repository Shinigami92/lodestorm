# Biome geography (planned)

Decided 2026-10-17, built in M4 step 6 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. The framework is built (step 6 A): a biome's barrier (walls or gaps), its passes (winding or bridges), its own kinds of areas and its hazard are data on `LocationBiome`, and the *Frost fields* use it (crevasses, snow bridges, ice shelf, frozen lake, slick ice; see [Generated outside world](../GAME_DESIGN.md#6-missions)). The other five biomes still have walls and winding passes, with their own numbers, scatter and tint.

## The other five biomes

Each picks a barrier, a pass style, its two area kinds and at most one hazard; the new ones (ridges, terraces, growth walls; slot canyons, trails, causeways, crust crossings, ramps; mud, vents, shards) are added to the framework as they come.

| Biome | Barrier | Passes | Own area kinds | Hazard | Plays like |
|---|---|---|---|---|---|
| *Dust flats* | walls: high layered mesas | **slot canyons**: narrow, deep, winding | **butte field** (rock pillars standing in the open, cover), **dry wash** (a long sandy riverbed as an area) | none | close corners and cover, the baseline |
| *Overgrowth* | low walls plus **growth walls** (giant fungal stalks and roots that block walking and shots, low on the camera's side like the rock) | **trails** through the growth, many loops | **mire** (shallow mud pools), **fungal grove** (stalks as cover, short sightlines) | **mud** slows players and aliens (to about 60 %) | a maze, ambushes |
| *Salt pans* | low walls and **gaps: sinkholes** (round pits in the pans) | **causeways**: raised crust ridges between brine flats | **sinkhole field** (an area dotted with pits, a maze in the open), **brine flat** (huge and empty) | none | the most open biome: range fights, spitters |
| *Ash fields* | high, sharp **ridges** (long rock spines instead of round mesas) and **gaps: lava channels** | **crust crossings**: narrow cooled bridges over the lava | **lava island** (reached by one crossing only), **vent field** | **vents**: glow and rumble for 1.5 s, then burst (damage in a small circle) | choke points and timing |
| *Glass plains* | **terraces**: the ground broken into slabs, the low steps between them are the walls, plus **shard fences** (lines of glass spikes that block walking, not shots) | **ramps** between the terraces | **terrace stairs** (an area climbing over several slabs by ramps), **shard garden** (spike clusters as cover) | **shards** on the ground in patches hurt while walked over (a little damage per second) | layered, shooting down from above |

- Gaps of other biomes keep the Frost fields' rules: the lip in their own look (salt crust, cooled lava), the walls behind it, only darters fly over (see [`aliens.md`](aliens.md)); the viewer draws lava channels red (the biome's gap tint).
- Hazards stay mild, readable and avoidable, never instant death, never in the landing yard or on a pass's lane; they hurt aliens too, so luring aliens into them is a tactic. Damaging ones (vents, shards) add damage to `GroundHazard`.

## Around it

- **Biomes and aliens:** the strains' biome leanings (see [`aliens.md`](aliens.md)) fit the barriers: burrowers on the open ground of the Dust flats and Salt pans, stalkers in the Overgrowth's cover, darters over the gaps and terraces of the Frost fields, Ash fields and Glass plains. Gaps make aliens walk around to the next bridge, which slows them.
- **Weather per biome** (art pass): particles and fog, cheap enough for VR: drifting sand, spores and mist in the hollows, snow flurries, heat shimmer, falling ash and the lava's glow, glare off the glass. The storm takes over at the end; the light stays muted so ores and aliens stand out.
- **Map parts in every biome:** the generic parts and the set pieces stay biome-neutral, re-dressed with the biome's materials later (a wreck in ice, a wreck in glass); each biome gets one generic part of its own with the assets (e.g. a frozen-in drill rig, a salt-crusted pump station).
- **Region sizes** stay as they are: the open biomes cover more ground with the same number of areas and keep their timers, the long sightlines make up for the walk (check in playtests).
- **Assets** (Blender, heavy on the GPU, with the art pass in M5, after the layouts work in greybox): per biome a ground texture set (floor, barrier, the barrier's lip), its scatter (5–8 rocks and plants) and its feature meshes (snow bridge, crust crossing, shard spikes, fungal stalks, lava).
