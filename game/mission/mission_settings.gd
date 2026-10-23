class_name MissionSettings
extends Resource
## Mission tuning values: the timer, the storm and how much harder bodies farther in are (what the
## missions on offer are made of: `VoyageSettings`). All values TBD (playtest). Target for real
## missions: about 15–30 min.

## Seconds from the start until the storm turns lethal in a standard mission; each mission scales
## it by its `MissionBrief.length`.
@export var duration: float = 300.0
## In the last seconds before the storm the ship's status color turns red and the ship pointer
## blinks (on a tier 1 body; see `warning_time_per_tier`).
@export var warning_time: float = 60.0
## Storm damage per second to players outside when the storm hits.
@export var storm_damage: float = 2.0
## How much the storm damage per second grows each second of storm (on a tier 1 body; see
## `storm_growth_per_tier`). With the defaults an unhurt player outside lasts about 9 s.
@export var storm_damage_growth: float = 2.0
## Seconds dead players lie outside after the mission is lost before they respawn aboard.
@export var respawn_delay: float = 3.0

@export_group("Tiers")
## Each tier above 1 (planets farther in, see `CelestialBody.tier`) adds this share of the aliens'
## health ...
@export var alien_health_per_tier: float = 0.3
## ... and of their damage (the nests: `VoyageSettings.nests_per_tier`).
@export var alien_damage_per_tier: float = 0.2
## The star's influence: each tier above 1 starts the storm's warning this many seconds earlier ...
@export var warning_time_per_tier: float = 10.0
## ... and adds this share of the storm damage's growth.
@export var storm_growth_per_tier: float = 0.25


## Seconds before the storm when the warning starts on a body of `tier`.
func warning_time_at(tier: int) -> float:
	return warning_time + warning_time_per_tier * (tier - 1)


## How much the storm damage per second grows each second of storm on a body of `tier`.
func storm_growth_at(tier: int) -> float:
	return storm_damage_growth * per_tier(storm_growth_per_tier, tier)


## How much more health aliens have on a body of `tier` than on a tier 1 one.
func alien_health_at(tier: int) -> float:
	return per_tier(alien_health_per_tier, tier)


## How much more damage aliens do on a body of `tier` than on a tier 1 one.
func alien_damage_at(tier: int) -> float:
	return per_tier(alien_damage_per_tier, tier)


## 1 on a tier 1 body, plus `share` for every tier above.
static func per_tier(share: float, tier: int) -> float:
	return 1.0 + share * (tier - 1)
