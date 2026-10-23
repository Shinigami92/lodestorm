class_name Projectile
extends Node3D
## Flies straight and disappears on its first hit or after its range. Casts a ray along each
## physics step, so fast projectiles can't tunnel through thin colliders. Damages the aliens and
## destructibles (nests) it hits; players are only blocked, there's no friendly fire. A piercing
## one flies on through the aliens it hits.

## Emitted when the projectile hits a collider (right before it disappears, unless it pierces it).
signal hit(collider: Object, hit_position: Vector3)

## In m/s.
var velocity: Vector3 = Vector3.ZERO
## Distance in m after which the projectile disappears.
var max_distance: float = 0.0
## Colliders the projectile flies through (e.g. the one who fired it).
var exclude: Array[RID] = []
## Damage dealt to what it hits, and its stagger and push (see `Hit`).
var damage: float = 0.0
var stagger: float = 0.0
var push: float = 0.0
## Who fired it (e.g. for the damage readout), or null, and with what.
var shooter: Node
var weapon_type: WeaponType
## Whether it flies on through the aliens it hits (each one is hit once).
var pierce: bool = false

var _travelled: float = 0.0


func _physics_process(delta: float) -> void:
	if move_to(global_position + velocity * delta) and _travelled >= max_distance:
		queue_free()


## Moves to `target` unless a collider is in the way; then it hits that and disappears (unless it
## pierces it). Returns whether it arrived. Only call during physics processing.
func move_to(target: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	while true:
		var query := PhysicsRayQueryParameters3D.create(
			global_position, target, PhysicsLayers.SHOTS
		)
		query.exclude = exclude
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			break
		var at: Vector3 = result["position"]
		_travelled += global_position.distance_to(at)
		global_position = at
		var collider: Object = result["collider"]
		var hitting := Hit.new(
			damage, stagger, push, velocity, global_position, shooter, weapon_type
		)
		if collider is Alien:
			var alien := collider as Alien
			DamageNumber.show_hit(shooter, alien, alien.take_hit(hitting))
		elif collider is Destructible:
			var body := collider as Destructible
			DamageNumber.show_hit(shooter, body, body.take_hit(hitting))
		hit.emit(collider, global_position)
		if pierce and collider is Alien:
			exclude.append((collider as Alien).get_rid())
			continue
		queue_free()
		return false
	_travelled += global_position.distance_to(target)
	global_position = target
	return true
