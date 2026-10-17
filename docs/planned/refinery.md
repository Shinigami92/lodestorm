# Refinery, crafted miners and timed upgrades (planned)

Decided 2026-10-17, built in M4 step 11 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. Today there is no refinery (the far end of the cargo bay is kept free for it), miners are unlimited and placed instantly with one shared set of upgrades, and upgrades and skills are bought instantly (see [Miners](../GAME_DESIGN.md#7-miners) and [Progression](../GAME_DESIGN.md#12-progression--upgrades)).

## Alloys

The refinery combines 2–3 ores into alloys. Higher upgrades cost alloys, so early ores stay useful. Refining takes real time, passing while playing and while away ("come back tomorrow"), and never blocks the story.

- **8 alloys** in four tiers of two, each made from a common ore as bulk, a mid ore and, from tier 2 on, a signature ore. Every ore goes into at least one alloy (every common and mid ore into two), so no ore becomes useless; more planets later add alloys the same way. Names are invented and untranslated like the ores, each with its own first letter; the signature alloys echo their signature ore. Greybox amounts per bar: 10 of the common ore, 5 of the mid ore, 3 of the signature ore.

| Tier | Alloy | Common (bulk) | Mid | Signature |
|---|---|---|---|---|
| 1 | **Cobrel** | Kyrite | Vyrel | – |
| 1 | **Gantrite** | Olvane | Halcyne | – |
| 2 | **Merisk** | Pallin | Duskine | Meridine |
| 2 | **Verdan** | Tessar | Ressa | Emerin |
| 3 | **Indite** | Kyrite | Halcyne | Indral |
| 3 | **Sylith** | Olvane | Vyrel | Selyx |
| 4 | **Noxar** | Pallin | Ressa | Noctile |
| 4 | **Auralt** | Tessar | Duskine | Aethrine |

- **Furnaces:** the ship starts without one. Quests unlock them one after another, up to four (see [`quests.md`](quests.md); until the quests exist, the debug overlay does). A furnace refines **one alloy at a time, in any amount** the hold pays for (paid when started); each alloy has its own time per bar (longer for higher tiers, greybox about 1, 3, 6 and 10 min), so a big batch can run for hours. Two alloys at once need two furnaces. Furnaces run on the wall clock: while playing, during runs and while the game is closed. Finished bars go to the rack by themselves.
- **Discovering recipes:** a recipe shows once all its ores have been in the hold (like the silos' "?"); until then it shows as "?" with the ores found so far, so nothing still to find is given away.
- **In the ship:** at the far end of the cargo bay, the furnaces stand in a row with pipes from the silo clusters (a locked one as a cold, dark shell), and beside them an **ingot rack** with a shelf per alloy, the bars stacking up glowing in the alloy's colors (unknown alloys a dark "?" shelf). The object is the menu: `interact` at a furnace opens it as a station; its card picks the recipe (`tab_prev`/`tab_next`) and the number of bars (steps), shows the cost with what the hold has and the time it takes, and "Start"; a running furnace shows its progress and the time left on its card and as a glow filling its door. The engineer explains it (see [`crew.md`](crew.md)). Each alloy gets a badge like the ores (its icon in its colors, a glow pattern), so costs and requests show alloys the same way.
- **What alloys are for:** crafted miners first (building them and their drill levels), part of every upgrade's cost from MK4 on (MK4–5 a tier-2 alloy, MK6–7 tier 3, MK8 tier 4, next to the ores from the cost rule in [`opening-planets.md`](opening-planets.md)), building the six prototype weapons (see [`weapons.md`](weapons.md)), and the station's requests (see [`station.md`](station.md)). The heat shield stays ores only, so opening planets never waits for a furnace.
- **Co-op:** per player, like the upgrades: each player refines from their own hold (see [`coop-ore.md`](coop-ore.md)) into their own rack, in their own save. The furnaces show the batches of the player using them; a guest's batches keep running in their own save.
- **Data:** an `ItemType` base for ores and alloys (name, colors, badge, glow pattern), so costs, the hold, requests, cards and tests handle both; an `AlloyType` with its recipe, tier and time per bar.

## Upgrades and skills take real time

Each MK level and each skill (rank) has its own time, from about 1 min for the first ones up to 6 h for the highest levels and the deepest skills. It's paid when started. There's no limit on how many run at once: a player can start as many as their hold pays for, so more mission runs are the limit, and they all run at the same time on the wall clock (also during runs and while the game is closed). One part's next level starts once the one before it is finished. A level takes effect when it's finished; one that finishes during a run takes effect when the player is back aboard. Starting is locked during a mission like buying today; running ones keep going. Shown in the world: the pip of a level under way fills slowly, the skill's point on the graph fills like a ring, and the card shows the time left; the quest board lists every running job (see [`quests.md`](quests.md)). Each player's own, in their own save. The heat shield isn't timed.

## Crafted miners

- **Ownership:** miners are built in the ship and kept. Each crafted miner is upgraded on its own, so it's worth protecting. Aliens only break it down (repairable, as today); it's **lost only when it's left on the planet** when the ship lifts off, or when every player dies.
- **Building:** in the miners' room on the maintenance pad, for ores and a tier-1 alloy, up to 6 per player. Each has its own number plate ("M-01") and its own parts and MK levels: drill, tank, hose and **plating** (its health). Building a lost one again costs the same.
- **Placing and picking up** takes a few seconds (3–10 s), with animations for both, so collecting the miners at the end of a run is a decision against the clock. The model also needs damage states for the art pass.
- **Miners per run:** each player takes up to 6 miners into a run, their crafted ones first, **standard-issue** ones filling the rest, so nobody is ever without miners. Standard-issue miners are free, refilled between runs, can't be upgraded, mine slower (greybox 75 %) and are never lost (they're the ship's). The miners left to place show as ticks on the suit ring when one is placed or picked up (see [`player-display.md`](player-display.md)). Today's unlimited miners go away.
- **The miners' room:** a bay along the wall with a cradle per crafted miner (6), empty ones offering "Build". Picking a miner puts it on the maintenance pad, whose parts are its upgrades; `tab_prev`/`tab_next` step through the miners. Its card shows its number, its parts' MK pips and whether it goes along on the next run.
- **Drill hardness:** harder and rarer ores need better drills, so miners have their own progression (`OreType.hardness`, unused today): common ores 0, mid ores 1, Meridine and Emerin 2, Indral and Selyx 3, Noctile and Aethrine 4. A drill's MK level sets how hard an ore it mines at full speed; a drill too soft still mines it at a quarter of the speed, so no ore is ever blocked, only slow. Standard-issue drills mine up to hardness 1 at full speed.
- **Later:** ore-specific drill heads from quest blueprints (+50 % on one band), shields and sentries (the support cluster, M7), more or faster furnaces as skills.
