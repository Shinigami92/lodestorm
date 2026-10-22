# Refinery, crafted miners and timed upgrades (planned)

Decided 2026-10-17, built in M4 step 11 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. The refinery and the timed upgrades and skills are built (see [Resources](../GAME_DESIGN.md#9-resources) and [Progression](../GAME_DESIGN.md#12-progression--upgrades)); miners are unlimited and placed instantly with one shared set of upgrades (see [Miners](../GAME_DESIGN.md#7-miners)).

## Alloys

The alloys, the furnaces, the ingot rack and recipe discovery are built (M4 step 11 A2, see [Resources](../GAME_DESIGN.md#9-resources)). Still planned:

- **What alloys are for:** crafted miners first (building them and their drill levels), part of every upgrade's cost from MK4 on (MK4–5 a tier-2 alloy, MK6–7 tier 3, MK8 tier 4, next to the ores from the cost rule in [Upgrade stations](../GAME_DESIGN.md#upgrade-stations)), building the six prototype weapons (see [`weapons.md`](weapons.md)), and the station's requests (see [`station.md`](station.md)). The heat shield stays ores only, so opening planets never waits for a furnace. The rack's card shows what an alloy is used for.
- **Unlocking furnaces:** the quests unlock them (see [`quests.md`](quests.md)); until then the debug overlay does.
- **The engineer** explains the refinery (see [`crew.md`](crew.md)).
- **Art pass (M5):** generated models of the furnaces and the rack.

## Crafted miners

- **Ownership:** miners are built in the ship and kept. Each crafted miner is upgraded on its own, so it's worth protecting. Aliens only break it down (repairable, as today); it's **lost only when it's left on the planet** when the ship lifts off, or when every player dies.
- **Building:** in the miners' room on the maintenance pad, for ores and a tier-1 alloy, up to 6 per player. Each has its own number plate ("M-01") and its own parts and MK levels: drill, tank, hose and **plating** (its health). Building a lost one again costs the same.
- **Placing and picking up** takes a few seconds (3–10 s), with animations for both, so collecting the miners at the end of a run is a decision against the clock. The model also needs damage states for the art pass.
- **Miners per run:** each player takes up to 6 miners into a run, their crafted ones first, **standard-issue** ones filling the rest, so nobody is ever without miners. Standard-issue miners are free, refilled between runs, can't be upgraded, mine slower (greybox 75 %) and are never lost (they're the ship's). The miners left to place show as ticks on the suit ring when one is placed or picked up (see [`player-display.md`](player-display.md)). Today's unlimited miners go away.
- **The miners' room:** a bay along the wall with a cradle per crafted miner (6), empty ones offering "Build". Picking a miner puts it on the maintenance pad, whose parts are its upgrades; `tab_prev`/`tab_next` step through the miners. Its card shows its number, its parts' MK pips and whether it goes along on the next run.
- **Drill hardness:** harder and rarer ores need better drills, so miners have their own progression (`OreType.hardness`, unused today): common ores 0, mid ores 1, Meridine and Emerin 2, Indral and Selyx 3, Noctile and Aethrine 4. A drill's MK level sets how hard an ore it mines at full speed; a drill too soft still mines it at a quarter of the speed, so no ore is ever blocked, only slow. Standard-issue drills mine up to hardness 1 at full speed.
- **Later:** ore-specific drill heads from quest blueprints (+50 % on one band), shields and sentries (the support cluster, M7), more or faster furnaces as skills.
