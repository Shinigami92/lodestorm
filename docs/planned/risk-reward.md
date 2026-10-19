# Reasons to move on (planned)

Decided 2026-10-17, built in M4 step 14 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. The goal (see [Reasons to move and to stay](../GAME_DESIGN.md#reasons-to-move-and-to-stay-risk-vs-reward)): standing at one spot until the timer runs low must not pay off. Today ore nodes never run out, nest hollows have no ore, and carried ore is only safe once its carrier is aboard, which ends the mission when everyone alive is. Decided elsewhere: miners draw raiders and the hive frenzies in the storm's warning ([`aliens.md`](aliens.md)), quest and bonus goals elsewhere on the map ([`quests.md`](quests.md)), destroyable nests ([`nests.md`](nests.md)).

## Nodes run dry

- **Amounts:** each node holds a limited amount, counted in fills of a standard miner (180 units): common nodes 2 fills, mid 1.5, signature 1 (rarer ore, smaller deposits). A bigger tank empties a node in fewer trips, never makes it bigger. So a good spot gives 2–3 fills and then the players move on.
- **Seeing it:** the crystals shrink in three steps as the node empties and dim a bit; a dry node turns to dark, cracked rock with a few dull stumps. A miner on a node that runs dry stops like a full one, but its lamp blinks amber instead of glowing steady (full): "move me". The ore scanner skill skips dry nodes; the navigator's hologram still shows every node (a preview before landing).

## Rich ore by the nests

Every nest hollow gets one rich field between its two nests: the region's rarest or second-rarest ore, its nodes holding double. That makes "richer ore right next to nests" real and gives destroying nests a reason beyond safety.

## A late deposit

Once per run, at a random time between 55 % and 75 % of the timer, a meteor comes down: a streak across the sky and a boom heard everywhere, then a beam in the ore's color rising from the impact for 30 s (visible over cliffs, like a landmark's), and the pilot on the radio ("Something came down out there, and it's glowing."). It lands in a far area picked when the location is generated: its crater is carved from the start (an empty crater looks like any other, so the ground and the navigation mesh never change mid-run), and the meteorite (the meteor crater part) and a field of the region's signature ore, nodes holding double, appear with the impact. Regions without a signature ore (Lisk, Mirr) get their rarest mid ore. The impact wakes the nearest nest: it sends a pack at once. Late, far, rich and guarded: the "one more trip" decision against the clock.

## Banking ore mid-run

A **cargo hatch** outside beside the ramp's foot: `interact` there unloads everything the player carries into the hold right away (safe from dying) without going aboard, so the mission goes on, solo players too. It costs the walk back, which is the decision: bank now, or push further with everything on the back. The ore flows into the hatch like through a hose (greybox about 2 s); the hold's silos fill as usual. Quest items stay carried (they count aboard).

## Later

Beacons to place from the miners' room (marking the way back) and barriers that open the far parts of regions with progress stay ideas in [`GAME_DESIGN.md`](../GAME_DESIGN.md#reasons-to-move-and-to-stay-risk-vs-reward).
