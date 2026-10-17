# Biome geography (planned)

Decided 2026-10-17, built in M4 step 6 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. Today every biome is the same generator with other numbers (`LocationBiome`: area sizes, pass widths, swells, wall heights, rock steps, scree) plus its scatter, ores and tint: the same area kinds, and everything that isn't open ground is raised rock (see [Generated outside world](../GAME_DESIGN.md#6-missions)).

## What makes a biome

A biome differs not only in its numbers, scatter and textures but in four things, each data on the biome (`LocationBiome`): its **barrier** (what keeps players out between the areas), its **passes** (what the ways between areas look like), **two area kinds of its own** on top of the shared ones, and at most **one hazard**. The same graph generator (areas, passes, loops, ore and nests by distance, set pieces) serves every biome; the difference is in how the ground is carved and dressed, so a new biome later picks a barrier, a pass style and its area kinds.

- **Walls and gaps:** besides raised rock (**walls**), biomes get **gaps**: ground lowered below the floor that nobody can enter (crevasses, lava channels, sinkholes). Players see and shoot across a gap but can't walk it: fights over a crevasse, spitters across a lava channel, aliens running around to the next bridge, while wall biomes stay close and twisting. Gaps never hide anything from the isometric camera and read well in VR. A gap's edge is blocked like the invisible walls, with a visible lip (snow, salt crust, cooled lava), so nobody falls in or gets stuck; only darters fly over (see [`aliens.md`](aliens.md)). The location's outer edge stays rock in every biome.
- **Hazards:** mild, readable and avoidable, never instant death, never in the landing yard or on a pass's lane; they hurt aliens too, so luring aliens into them is a tactic.
- **Heightfield only,** as for the map parts: no caves, overhangs or floating islands. Crevasses, channels and sinkholes are lowered ground, terraces and ridges raised ground; arches, if ever, are props in map parts.

## The six biomes

| Biome | Barrier | Passes | Own area kinds | Hazard | Plays like |
|---|---|---|---|---|---|
| *Dust flats* | walls: high layered mesas | **slot canyons**: narrow, deep, winding | **butte field** (rock pillars standing in the open, cover), **dry wash** (a long sandy riverbed as an area) | none | close corners and cover, the baseline |
| *Overgrowth* | low walls plus **growth walls** (giant fungal stalks and roots that block walking and shots, low on the camera's side like the rock) | **trails** through the growth, many loops | **mire** (shallow mud pools), **fungal grove** (stalks as cover, short sightlines) | **mud** slows players and aliens (to about 60 %) | a maze, ambushes |
| *Frost fields* | **gaps: crevasses** splitting wide ice sheets; walls at the edge | **snow bridges**: short, narrow crossings over the crevasses | **ice shelf** (a huge flat area at a crevasse field), **frozen lake** (round, flat, slick) | **slick ice** on frozen lakes (players and aliens slide a little) | wide, long sightlines, choke points at the bridges |
| *Salt pans* | low walls and **gaps: sinkholes** (round pits in the pans) | **causeways**: raised crust ridges between brine flats | **sinkhole field** (an area dotted with pits, a maze in the open), **brine flat** (huge and empty) | none | the most open biome: range fights, spitters |
| *Ash fields* | high, sharp **ridges** (long rock spines instead of round mesas) and **gaps: lava channels** | **crust crossings**: narrow cooled bridges over the lava | **lava island** (reached by one crossing only), **vent field** | **vents**: glow and rumble for 1.5 s, then burst (damage in a small circle) | choke points and timing |
| *Glass plains* | **terraces**: the ground broken into slabs, the low steps between them are the walls, plus **shard fences** (lines of glass spikes that block walking, not shots) | **ramps** between the terraces | **terrace stairs** (an area climbing over several slabs by ramps), **shard garden** (spike clusters as cover) | **shards** on the ground in patches hurt while walked over (a little damage per second) | layered, shooting down from above |

## Around it

- **Biomes and aliens:** the strains' biome leanings (see [`aliens.md`](aliens.md)) fit the barriers: burrowers on the open ground of the Dust flats and Salt pans, stalkers in the Overgrowth's cover, darters over the gaps and terraces of the Ash fields and Glass plains. Gaps make aliens walk around to the next bridge, which slows them.
- **Weather per biome** (art pass): particles and fog, cheap enough for VR: drifting sand, spores and mist in the hollows, snow flurries, heat shimmer, falling ash and the lava's glow, glare off the glass. The storm takes over at the end; the light stays muted so ores and aliens stand out.
- **Map parts in every biome:** the generic parts and the set pieces stay biome-neutral, re-dressed with the biome's materials later (a wreck in ice, a wreck in glass); each biome gets one generic part of its own with the assets (e.g. a frozen-in drill rig, a salt-crusted pump station).
- **Region sizes** stay as they are: the open biomes cover more ground with the same number of areas and keep their timers, the long sightlines make up for the walk (check in playtests).
- **Tools:** the location viewer draws the barriers (walls brown, gaps dark blue or red), the hazards and the new area kinds; the seed sweep checks per biome that every area is reachable, no spot is stuck, no hazard lies on a lane or in the landing yard, and every bridge connects.
- **Assets** (Blender, heavy on the GPU, with the art pass in M5, after the layouts work in greybox): per biome a ground texture set (floor, barrier, the barrier's lip), its scatter (5–8 rocks and plants) and its feature meshes (snow bridge, crust crossing, shard spikes, fungal stalks, lava).
