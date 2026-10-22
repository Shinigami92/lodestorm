# Refinery, crafted miners and timed upgrades (planned)

Decided 2026-10-17, built in M4 step 11 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. The refinery, the timed upgrades and skills and the crafted miners (the bay, the rules, placing and picking up taking time, the suit ring's ticks, drill hardness) are built (see [Resources](../GAME_DESIGN.md#9-resources), [Progression](../GAME_DESIGN.md#12-progression--upgrades) and [Miners](../GAME_DESIGN.md#7-miners)); still planned: alloys in the costs (M4 step 11 D2).

## Alloys

The alloys, the furnaces, the ingot rack and recipe discovery are built (M4 step 11 A2, see [Resources](../GAME_DESIGN.md#9-resources)). Still planned:

- **What alloys are for:** crafted miners first (building them and their drill levels), part of every upgrade's cost from MK4 on (MK4–5 a tier-2 alloy, MK6–7 tier 3, MK8 tier 4, next to the ores from the cost rule in [Upgrade stations](../GAME_DESIGN.md#upgrade-stations)), building the six prototype weapons (see [`weapons.md`](weapons.md)), and the station's requests (see [`station.md`](station.md)). The heat shield stays ores only, so opening planets never waits for a furnace. The rack's card shows what an alloy is used for.
- **Which alloy per level** (decided 2026-10-22, step 11 D2): the alloy of the previous planet's signature ore, so it can be refined before the level opens: MK4 Merisk, MK5 Verdan, MK6 Indite, MK7 Sylith, MK8 Noxar (Auralt stays for Zenith and the station's requests). In bars at scale 1, next to the unchanged ores: MK4 4, MK5 6, MK6 8, MK7 10, MK8 12, scaled by `Upgrade.cost_scale` and rounded to whole bars (at least 1), for every upgrade, the miners' parts too (`MkCost` gets the alloy and its bars). One furnace makes MK4's 4 Merisk in 12 min (the level takes 15), MK8's 12 Noxar in 2 h (the level 6 h). **TBD (playtest)**.
- **On the cards:** the alloy's ingot badge in the cost row after the ores, red when short; the ingot rack's card gets a "Used for" line ("Upgrades MK4", "Upgrades MK6, Kith").
- **Jobs under way** keep what was paid (saved with them), and "Stop" gives back exactly that; saved jobs from before give back the ores only.
- **The prototypes' build cost** adds bars of the alloy of their own signature ore, the ores staying as they are: Clout 6 Verdan, Kith 8 Indite, Fulgen 10 Sylith, Mantle 10 Sylith, Nadir 12 Noxar, Zenith 15 Auralt (**TBD (playtest)**). Colony arms and converted tools stay ores only.
- **Every cost** becomes `Dictionary[ItemType, int]` (`WeaponType.build_cost` takes alloys too), and the ore-only payments and `ores()` snapshots go away.
- **Until the quests** unlock the furnaces (step 16 C), MK4 and up and the prototypes need the debug overlay's furnaces and rack (like the miners' Cobrel).
- **Unlocking furnaces:** the quests unlock them (see [`quests.md`](quests.md)); until then the debug overlay does.
- **The engineer** explains the refinery (see [`crew.md`](crew.md)).
- **Art pass (M5):** generated models of the furnaces and the rack.

## Crafted miners

Building, the cradles, the parts with plating, six per run with standard-issue ones filling up, picking up with `interact`, losing them (M4 step 11 C1), placing and picking up taking time and the suit ring's ticks (C2), and drill hardness (D1) are built (see [Miners](../GAME_DESIGN.md#7-miners)). Still planned:

- **Art pass (M5):** a kneeling clip for placing and picking up, and the model's damage states.
- **Later:** ore-specific drill heads from quest blueprints (+50 % on one band), shields and sentries (the support cluster, M7), more or faster furnaces as skills.
