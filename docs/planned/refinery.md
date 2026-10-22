# Refinery, crafted miners and timed upgrades (planned)

Decided 2026-10-17, built in M4 step 11 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. The refinery, the timed upgrades and skills and the crafted miners' bay and rules are built (see [Resources](../GAME_DESIGN.md#9-resources), [Progression](../GAME_DESIGN.md#12-progression--upgrades) and [Miners](../GAME_DESIGN.md#7-miners)); still planned for the miners: placing and picking up taking time, the suit ring's ticks and drill hardness.

## Alloys

The alloys, the furnaces, the ingot rack and recipe discovery are built (M4 step 11 A2, see [Resources](../GAME_DESIGN.md#9-resources)). Still planned:

- **What alloys are for:** crafted miners first (building them and their drill levels), part of every upgrade's cost from MK4 on (MK4–5 a tier-2 alloy, MK6–7 tier 3, MK8 tier 4, next to the ores from the cost rule in [Upgrade stations](../GAME_DESIGN.md#upgrade-stations)), building the six prototype weapons (see [`weapons.md`](weapons.md)), and the station's requests (see [`station.md`](station.md)). The heat shield stays ores only, so opening planets never waits for a furnace. The rack's card shows what an alloy is used for.
- **Unlocking furnaces:** the quests unlock them (see [`quests.md`](quests.md)); until then the debug overlay does.
- **The engineer** explains the refinery (see [`crew.md`](crew.md)).
- **Art pass (M5):** generated models of the furnaces and the rack.

## Crafted miners

Building, the cradles, the parts with plating, six per run with standard-issue ones filling up, picking up with `interact` and losing them are built (M4 step 11 C1, see [Miners](../GAME_DESIGN.md#7-miners)). Still planned:

- **Placing and picking up** take time (greybox 3 s and 5 s, **TBD (playtest)**), so collecting the miners at the end of a run is a decision against the clock. The player stands still with the weapon lowered; moving, dashing or attacking cancels it (nothing lost, the miner stays where it was), taking damage doesn't. Greybox look: the miner lowers from the player's back to the node and unfolds its legs, and the reverse. Two synthesized sounds: the unfold (a servo whine ending in today's thud) and the fold (the reverse, a latch at the end). Art pass: a kneeling clip and the model's damage states.
- **Suit ring:** six short ticks along the ring's top gap in the miner color: crafted ones bright, standard-issue dimmer, placed ones as outlines; shown for 3 s when one is placed or picked up, and while the player stands next to a miner (see [`player-display.md`](player-display.md)).
- **Drill hardness:** harder and rarer ores need better drills, so miners have their own progression (`OreType.hardness`, unused today): common ores 0, mid ores 1, Meridine and Emerin 2, Indral and Selyx 3, Noctile and Aethrine 4. A drill's MK level sets how hard an ore it mines at full speed; a drill too soft still mines it at a quarter of the speed, so no ore is ever blocked, only slow. Standard-issue drills mine up to hardness 1 at full speed.
- **Later:** ore-specific drill heads from quest blueprints (+50 % on one band), shields and sentries (the support cluster, M7), more or faster furnaces as skills.
