class_name MissionSettings
extends Resource
## Mission tuning values; later one per mission (location, timer, difficulty). All values TBD
## (playtest). Target for real missions: about 15–30 min.

## Seconds from the start until the storm turns lethal. Greybox: short, for the small test map.
@export var duration: float = 300.0
## In the last seconds before the storm the ship's beacon turns red and blinks.
@export var warning_time: float = 60.0
