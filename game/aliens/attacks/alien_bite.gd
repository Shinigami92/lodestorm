class_name AlienBite
extends AlienAttack
## A quick strike at a target in reach, without a wind-up (the jaw snaps, the blades strike).


func act(alien: Alien, _elapsed: float) -> bool:
	alien.strike(alien.target, damage)
	return true


func _in_range(alien: Alien, target: Node3D, distance: float) -> bool:
	return distance <= alien.reach_to(target, reach)
