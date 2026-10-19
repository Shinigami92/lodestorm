class_name AlienHook
extends AlienAttack
## A stalker's flesh hook: after the wind-up it shoots a barbed hook on a sinew line (`FleshHook`)
## straight at its target; rock stops it and a step aside dodges it. A player it catches takes
## `damage` and is held to `snare` of their walking speed for `snare_time` (the dash still gets
## away), the line staying on them meanwhile. It doesn't pull: being dragged would turn a VR
## player's view. It only hooks once it has been seen (not while it hides: from hiding it strikes).

## The target has to be between these distances to start (horizontally, in m).
@export var min_range: float = 6.0
@export var max_range: float = 10.0
## Speed of the hook, in m/s; it flies at most a bit farther than `max_range`.
@export var hook_speed: float = 24.0
## The share of the walking speed a caught player keeps, and for how long (s).
@export var snare: float = 0.5
@export var snare_time: float = 1.5
## Where the hook leaves, from the alien (its local axes: -z forward, in m).
@export var mouth := Vector3(0.0, 1.4, -0.5)
## The target may stand this much higher or lower (m).
@export var max_height_difference: float = 2.0


## It doesn't come closer for this one.
func approach() -> float:
	return max_range


func begin(alien: Alien) -> void:
	var target: Node3D = alien.target
	if not is_instance_valid(target) or not alien.is_inside_tree():
		return
	var aim: Vector3 = target.global_position + Vector3.UP * FleshHook.CHEST_HEIGHT
	FleshHook.launch(alien, self, alien.global_transform * mouth, aim)


func act(_alien: Alien, _elapsed: float) -> bool:
	return true


func _in_range(alien: Alien, target: Node3D, distance: float) -> bool:
	if alien.cloaking and alien.cloaking.is_cloaked():
		return false
	if distance < min_range or distance > max_range:
		return false
	return absf(target.global_position.y - alien.global_position.y) <= max_height_difference
