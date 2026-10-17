# Opening planets (planned)

Decided 2026-10-17, built in M4 step 4 (see [`PLAN.md`](../PLAN.md)). All values **TBD (playtest)**. Today only Torvane and Lisk are open (the debug overlay's "Unlock regions" opens the rest), every flight takes the same time, MK levels go up to MK3, and the tiers are data without effect.

## The heat shield

- **Opening planets:** the next planet inwards opens with the ship's **heat shield** in the engine room, one MK level per planet, paid mostly with the current planet's signature ore, so better ores open the way. MK1 is the bare drive core (Torvane and Lisk); MK2 opens Vehra, MK3 Cassor and Mirr, MK4 Gaulm's moons, MK5 Skelde, MK6 Zairen. A body is open when its tier is at most the shield's level + 1; moons open with their planet. The story wraps it later but never adds a second gate. Every region of a reached body is open; the far parts of a region may open with progress later (barriers, see [`GAME_DESIGN.md`](../GAME_DESIGN.md#reasons-to-move-and-to-stay-risk-vs-reward)).
- **The station:** the greybox reactor becomes the drive core with the heat shield around it, a ring of plates, one per planet inwards (Vehra, Cassor, Gaulm's moons, Skelde, Zairen; Torvane is the bare core). It's a station like the upgrade stations: the camera frames the core, the next plate is selectable, and its card says what it opens ("Heat shield MK2 — opens Vehra"), its cost with how much of it is paid so far and what the hold has, "Make it the ship's project" and "Pay the rest from the hold". Installed plates glow, later ones show as dim outlines, so the length of the way stays visible. The engineer explains it (see [`crew.md`](crew.md)).
- **Paid from the hauls:** the host picks the next plate as the ship's current project; every run that comes back pays into it first, with exactly the ores it still needs, before the haul is shared, so in co-op everyone pays the same and nobody's hold is touched (see [`coop-ore.md`](coop-ore.md)). The host can also pay what's missing from their own hold at any time (solo: the player, from their silos). The plate fills up on the drive core like a silo and is installed once paid. Only the host picks the project (the ship and the open bodies are the host's save); guests see the card with a hint instead. Locked during a mission, like the other stations. Installing is instant (not timed like the upgrades, see [`refinery.md`](refinery.md)), so opening a planet never waits.
- **Costs** (starting values), mostly the current planet's signature ore (about 3–4 good runs of it, less than a full silo) and a mid ore found there: Vehra 300 Meridine and 400 Vyrel, Cassor 300 Emerin and 400 Halcyne, Gaulm's moons 300 Indral and 400 Ressa, Skelde 300 Selyx and 400 Duskine, Zairen 300 Noctile and 500 Duskine. Ores only, never alloys.
- **Saved:** the shield's level is part of the host's save (the ship's state, replacing today's `Region.unlocked` in the shared data), and so is where the ship is (its body; bodies are sub-resources of `star_system.tres`, so it needs an id of its own), so the navigator and the flight time are right after loading.
- **The navigator's card of a locked body** says what it needs ("Needs heat shield MK2 (engine room)", with the cost's ores as badges).
- **Debug overlay:** install the next level, or open everything.

## What tiers scale

- **Aliens:** per tier above 1, alien health +30 %, alien damage +20 %, nests +10 %. That keeps pace with one damage and one armor MK level per planet (+25 % each), so each new planet feels a bit harder until the players have upgraded. Each tier also brings two new strains (see [`aliens.md`](aliens.md)).
- **The star's influence** (the star is getting unstable, see [Story](../GAME_DESIGN.md#story-and-setting-draft)): per tier above 1, the storm's warning starts 10 s earlier (60 s on Torvane, 110 s on Zairen) and its damage's growth rises by 25 % (2 → 4.5 HP/s per second); the starting damage and the timer stay. With more armor inwards, the time to get aboard stays about the same, but the warning gets longer and the last seconds harsher. No other hazards from the star; the biomes have their own (see [`biomes.md`](biomes.md)).

## MK levels per planet

- **Each opened planet raises the highest MK level** that can be bought by one: MK3 while only Torvane is open, MK4 with Vehra, up to MK8 with Zairen. The upgrades grow with the campaign instead of all being bought on the first planet.
- **Co-op cap:** each body's maximum MK level is the same number, its tier + 2 (the tier sync, see [Co-op progression](../GAME_DESIGN.md#co-op-progression)).

## Which ores a level costs

The rule for weapons, armor, miners and skills (the amounts stay **TBD (playtest)**): each MK level costs a common and a mid ore, and from MK3 on also the signature ore of the planet that brought the level (MK3 Meridine, MK4 Emerin, MK5 Indral, MK6 Selyx, MK7 Noctile, MK8 Aethrine). Skills the same by their depth in the tree: the first ones commons, then mid ores, deep ones a signature ore. So each planet's signature ore buys that planet's MK level and the way onward (the heat shield). From MK4 on, alloys take over part of the cost (see [`refinery.md`](refinery.md)).

## Flights between bodies

Flights cost nothing (no fuel); a flight to another body has a longer departure in space (greybox 14 s instead of 6 s, the destination growing in the windows); within one body nothing changes.
