class_name SlowEffect
extends WeaponEffect
## Slows what a hit touches (Jag's saw): the alien keeps `factor` of its speed for `seconds`, so a
## weapon hitting it often keeps it slow while it touches it (see `AlienStatus.slow`). All values
## TBD (playtest).

## Share of its speed an alien keeps.
@export_range(0.0, 1.0) var factor: float = 0.5
## Seconds it lasts after each hit.
@export var seconds: float = 0.25


func add_to(hit: Hit, _weapon: Weapon) -> void:
	hit.slow = minf(hit.slow, factor)
	hit.slow_time = maxf(hit.slow_time, seconds)
