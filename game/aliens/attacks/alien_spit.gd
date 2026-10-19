class_name AlienSpit
extends AlienAttack
## A spitter's lob: after the wind-up it spits a glob of acid in an arc at where its target stands
## (`AcidGlob`), which shows where it lands as a ring on the ground. It splashes `damage` on whoever
## is within `splash_radius` there and leaves a burning puddle (`AcidPuddle`) that hurts players
## and miners, not aliens. It lobs from `min_range` up to `reach` away, over rocks and gaps.

## The target has to be at least this far away to start (horizontally, in m).
@export var min_range: float = 4.0
## Speed of the glob along the ground, in m/s; its flight takes at least `min_flight_time`.
@export var glob_speed: float = 11.0
@export var min_flight_time: float = 0.7
## How high the arc rises above the line from the mouth to the landing spot, per m of distance.
@export var arc_per_meter: float = 0.25
## Where the glob leaves, from the alien (its local axes: -z forward, in m).
@export var mouth := Vector3(0.0, 0.8, -0.7)
## Splash at the landing spot, in m.
@export var splash_radius: float = 1.2
## The puddle: its size (m), how long it burns (s) and its damage per second.
@export var puddle_radius: float = 1.5
@export var puddle_time: float = 4.0
@export var puddle_damage: float = 6.0


func begin(alien: Alien) -> void:
	var target: Node3D = alien.target
	if not is_instance_valid(target) or not alien.is_inside_tree():
		return
	alien.play_attack()
	AcidGlob.launch(alien, self, alien.global_transform * mouth, target.global_position)


func act(_alien: Alien, _elapsed: float) -> bool:
	return true


func _in_range(_alien: Alien, _target: Node3D, distance: float) -> bool:
	return distance >= min_range and distance <= reach
