class_name MissionSettings
extends Resource
## Mission tuning values, and what the missions on offer at the holo table are made of. All values
## TBD (playtest). Target for real missions: about 15–30 min.

## Seconds from the start until the storm turns lethal in a standard mission; each mission scales
## it by its `MissionBrief.length`.
@export var duration: float = 300.0
## In the last seconds before the storm the ship's status color turns red and the ship pointer
## blinks.
@export var warning_time: float = 60.0
## Storm damage per second to players outside when the storm hits.
@export var storm_damage: float = 2.0
## How much the storm damage per second grows each second of storm. With the defaults an unhurt
## player outside lasts about 9 s.
@export var storm_damage_growth: float = 2.0
## Seconds dead players lie outside after the mission is lost before they respawn aboard.
@export var respawn_delay: float = 3.0

@export_group("Offers")
## Where missions go: one is offered per open region of its planets and moons.
@export var system: StarSystem
## How many of its biome's nests a location has, per difficulty (a region's danger: easy, normal,
## hard).
@export var nest_factors: PackedFloat32Array = [0.6, 1.0, 1.4]
