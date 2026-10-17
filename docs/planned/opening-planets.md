# Opening planets (planned)

Decided 2026-10-17, built in M4 step 4 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. The heat shield that opens the planets, the longer flights between bodies and the navigator's locked cards are built (step 4 A, see [Opening planets](../GAME_DESIGN.md#6-missions)); still to come (step 4 B): today MK levels go up to MK3, and the tiers only decide what the heat shield reaches.

## What tiers scale

- **Aliens:** per tier above 1, alien health +30 %, alien damage +20 %, nests +10 %. That keeps pace with one damage and one armor MK level per planet (+25 % each), so each new planet feels a bit harder until the players have upgraded. Each tier also brings two new strains (see [`aliens.md`](aliens.md)).
- **The star's influence** (the star is getting unstable, see [Story](../GAME_DESIGN.md#story-and-setting-draft)): per tier above 1, the storm's warning starts 10 s earlier (60 s on Torvane, 110 s on Zairen) and its damage's growth rises by 25 % (2 → 4.5 HP/s per second); the starting damage and the timer stay. With more armor inwards, the time to get aboard stays about the same, but the warning gets longer and the last seconds harsher. No other hazards from the star; the biomes have their own (see [`biomes.md`](biomes.md)).

## MK levels per planet

- **Each opened planet raises the highest MK level** that can be bought by one: MK3 while only Torvane is open, MK4 with Vehra, up to MK8 with Zairen. The upgrades grow with the campaign instead of all being bought on the first planet.
- **Co-op cap:** each body's maximum MK level is the same number, its tier + 2 (the tier sync, see [Co-op progression](../GAME_DESIGN.md#co-op-progression)).

## Which ores a level costs

The rule for weapons, armor, miners and skills (the amounts stay **TBD (playtest)**): each MK level costs a common and a mid ore, and from MK3 on also the signature ore of the planet that brought the level (MK3 Meridine, MK4 Emerin, MK5 Indral, MK6 Selyx, MK7 Noctile, MK8 Aethrine). Skills the same by their depth in the tree: the first ones commons, then mid ores, deep ones a signature ore. So each planet's signature ore buys that planet's MK level and the way onward (the heat shield). From MK4 on, alloys take over part of the cost (see [`refinery.md`](refinery.md)).
