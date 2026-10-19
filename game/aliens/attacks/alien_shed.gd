class_name AlienShed
extends AlienAttack
## The Ravager shedding the aliens riding on its back: after the wind-up (its pods flaring),
## `count` aliens of `strain` drop off around it as hunters, as strong as it is for its body's
## tier, unless the cap on living aliens is reached (the nests', `AlienNestSettings.alien_cap`; read
## from the settings, since nothing a strain loads may reach `AlienNest`).

const NEST_SETTINGS: AlienNestSettings = preload("res://game/aliens/nest/alien_nest_settings.tres")

## Who rides on its back.
@export var strain: AlienStrain
## How many drop off each time.
@export var count: int = 3
## It sheds while its target is this close (horizontally, m).
@export var max_range: float = 20.0
## How far from its center they land (horizontally, m).
@export var spread: float = 3.5


## It doesn't come closer for this one.
func approach() -> float:
	return max_range


func act(alien: Alien, _elapsed: float) -> bool:
	var parent := alien.get_parent() as Node3D
	for i: int in count:
		var living: float = Alien.living_load(alien.get_tree())
		if living + strain.cap_share > NEST_SETTINGS.alien_cap():
			break
		var shed: Alien = strain.spawn(Alien.Role.HUNTER)
		shed.health_factor = alien.health_factor
		shed.damage_factor = alien.damage_factor
		var angle: float = alien.global_rotation.y + TAU * (float(i) + 0.5) / count
		var out := Vector3(sin(angle), 0.0, cos(angle))
		shed.position = parent.to_local(alien.global_position + out * spread)
		# Facing away from it.
		shed.basis = Basis(Vector3.UP, atan2(-out.x, -out.z))
		parent.add_child(shed)
	return true


func _in_range(_alien: Alien, _target: Node3D, distance: float) -> bool:
	return distance <= max_range
