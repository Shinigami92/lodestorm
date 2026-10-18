class_name Projectile
extends Node3D
## Flies straight and disappears on its first hit or after its range. Casts a ray along each
## physics step, so fast projectiles can't tunnel through thin colliders. Damages the aliens it
## hits; players are only blocked, there's no friendly fire.

## Emitted when the projectile hits a collider, right before it disappears.
signal hit(collider: Object, hit_position: Vector3)

## In m/s.
var velocity: Vector3 = Vector3.ZERO
## Distance in m after which the projectile disappears.
var max_distance: float = 0.0
## Colliders the projectile flies through (e.g. the one who fired it).
var exclude: Array[RID] = []
## Damage dealt to an alien it hits, and its stagger and push (see `Hit`).
var damage: float = 0.0
var stagger: float = 0.0
var push: float = 0.0
## Who fired it (e.g. for the damage readout), or null.
var shooter: Node

var _travelled: float = 0.0


func _physics_process(delta: float) -> void:
	if move_to(global_position + velocity * delta) and _travelled >= max_distance:
		queue_free()


## Moves to `target` unless a collider is in the way; then it hits that and disappears.
## Returns whether it arrived. Only call during physics processing.
func move_to(target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position, target, PhysicsLayers.SHOTS)
	query.exclude = exclude
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		global_position = result["position"] as Vector3
		var collider: Object = result["collider"]
		if collider is Alien:
			var alien := collider as Alien
			var dealt: float = alien.take_hit(
				Hit.new(damage, stagger, push, velocity, global_position, shooter)
			)
			DamageNumber.show_hit(shooter, alien, dealt)
		hit.emit(collider, global_position)
		queue_free()
		return false
	_travelled += global_position.distance_to(target)
	global_position = target
	return true
