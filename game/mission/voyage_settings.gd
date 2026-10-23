class_name VoyageSettings
extends Resource
## What the missions on offer at the holo table are made of (see `Voyage`). All values TBD
## (playtest).

## Where missions go: one is offered per open region of its planets and moons.
@export var system: StarSystem
## How many of its biome's nests a location has, per difficulty (a region's danger: easy, normal,
## hard).
@export var nest_factors: PackedFloat32Array = [0.6, 1.0, 1.4]
## Each tier above 1 (planets farther in, see `CelestialBody.tier`) adds this share of the nests a
## location has.
@export var nests_per_tier: float = 0.1
## How many open areas a generated location of a standard mission has; each mission scales it by
## its `MissionBrief.length` (a longer run gets a bigger location).
@export var location_areas: int = 11


## How many of its biome's nests a location has (1: as many as the biome says) at `difficulty` on a
## body of `tier`.
func nest_factor_at(difficulty: MissionBrief.Difficulty, tier: int) -> float:
	return nest_factors[difficulty] * MissionSettings.per_tier(nests_per_tier, tier)
