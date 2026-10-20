class_name AlienPounce
extends AlienAttack
## A leap at the target from a few meters away: after the wind-up (crouching), it leaps
## `leap_distance` towards where the target stood when the wind-up ended, so a sidestep or a dash
## dodges it, and hits the target if it comes within `reach` on the way. Then it stands still for
## `recovery`.

## How far past the target's spot it leaps, so it lands on it rather than in front of it (m).
const OVERSHOOT: float = 0.5

## The target has to be between these distances to start (horizontally, in m).
@export var min_range: float = 2.5
@export var max_range: float = 5.0
## How far it leaps at most (m); it stops early where it would land behind the target's spot.
@export var leap_distance: float = 4.0
## Speed of the leap in m/s.
@export var leap_speed: float = 12.0
## How high the body arcs in the middle of the leap (m).
@export var leap_height: float = 0.5
## The target may stand this much higher or lower (m).
@export var max_height_difference: float = 1.5


func moves() -> bool:
	return true


func begin(alien: Alien) -> void:
	var offset: Vector3 = alien.target.global_position - alien.global_position
	offset.y = 0.0
	alien.lunge(offset.normalized(), minf(leap_distance, offset.length() + OVERSHOOT), leap_height)


func act(alien: Alien, elapsed: float) -> bool:
	var travelled: float = elapsed * leap_speed
	if not alien.lunge_hit and _touches(alien):
		alien.strike(alien.target, damage)
		alien.lunge_hit = true
	return alien.lunge_step(leap_speed, travelled)


func _in_range(alien: Alien, target: Node3D, distance: float) -> bool:
	if distance < min_range or distance > max_range:
		return false
	return absf(target.global_position.y - alien.global_position.y) <= max_height_difference


func _touches(alien: Alien) -> bool:
	if not is_instance_valid(alien.target):
		return false
	if absf(alien.target.global_position.y - alien.global_position.y) > max_height_difference:
		return false
	return alien.horizontal_distance(alien.target) <= alien.reach_to(alien.target, reach)
