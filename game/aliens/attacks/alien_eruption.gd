class_name AlienEruption
extends AlienAttack
## A burrower's bite from below (see `AlienStrain.burrows`): once it's under its target, the ground
## bulges for `wind_up` (the telegraph: whoever keeps moving gets away), then it bursts up and
## bites whoever is still within `reach`. Afterwards it stays up for a while (`surface_time`) and
## can be hit. Only starts from under the ground (`underground`).

## How close under its target it has to come to start (horizontally, center to center, in m).
@export var trigger_range: float = 0.8


func begin(alien: Alien) -> void:
	alien.surface()


func act(alien: Alien, _elapsed: float) -> bool:
	var target: Node3D = alien.target
	if (
		is_instance_valid(target)
		and alien.horizontal_distance(target) <= alien.reach_to(target, reach)
	):
		alien.strike(target, damage)
	return true


func approach() -> float:
	return trigger_range


func _in_range(alien: Alien, target: Node3D, distance: float) -> bool:
	return distance <= alien.reach_to(target, trigger_range)
