class_name SpinningPart
extends Node3D
## A part of a weapon's model that turns around its own Z axis as the weapon's trigger winds up
## (`Weapon.wind`: Grindle's barrels spinning). A child of the weapon's scene.

## Radians per second at full speed.
@export var speed: float = 30.0

@onready var _weapon: Weapon = owner as Weapon


func _process(delta: float) -> void:
	if _weapon and _weapon.wind > 0.0:
		rotate_object_local(Vector3.FORWARD, _weapon.wind * speed * delta)
