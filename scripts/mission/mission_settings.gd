class_name MissionSettings
extends Resource
## Mission tuning values; later one per mission (location, timer, difficulty). All values TBD
## (playtest). Target for real missions: about 15–30 min.

## Seconds from the start until the storm turns lethal. Greybox: short, for the small test map.
@export var duration: float = 300.0
## In the last seconds before the storm the ship's beacon turns red and blinks.
@export var warning_time: float = 60.0
## Storm damage per second to players outside when the storm hits.
@export var storm_damage: float = 2.0
## How much the storm damage per second grows each second of storm. With the defaults an unhurt
## player outside lasts about 9 s.
@export var storm_damage_growth: float = 2.0
## Seconds dead players lie outside after the mission is lost before they respawn aboard.
@export var respawn_delay: float = 3.0
