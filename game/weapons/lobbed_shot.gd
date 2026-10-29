class_name LobbedShot
extends Node3D
## What a `LobDelivery` lobs: it flies in an arc from the muzzle to its landing spot, over rocks
## and cliffs as long as the arc clears them. Casts a ray along each physics step: it lands early
## on rock, the ground or a nest in its way, and on an alien in its way (unless `through_aliens`);
## players don't stop it. Landing, it blasts (Tremor's shell, see `Blast`); a `PlacedCharge` stays
## on the ground instead. Its model is its scene's children.

## Where it leaves and lands (global), how high the arc rises above the line between them and how
## long it flies.
var start: Vector3
var landing: Vector3
var arc_height: float = 1.0
var flight_time: float = 1.0
## The hit its blast strikes with (see `Blast.explode`), the blast's radius and sound.
var hit: Hit
var blast_radius: float = 3.0
var blast_sound: Sound
## Colliders it flies through (the one who fired it).
var exclude: Array[RID] = []
## Whether it flies through aliens (a charge tossed past them) instead of landing on them.
var through_aliens: bool = false

var _elapsed: float = 0.0
var _landed: bool = false
## The alien or destructible it hit, or null: it takes the full blast.
var _direct: Node3D


func _physics_process(delta: float) -> void:
	if _landed:
		return
	_elapsed += delta
	var t: float = minf(_elapsed / maxf(flight_time, 0.01), 1.0)
	if not _move_to(position_at(t)) and t >= 1.0:
		_landed = true
		_land(landing)


## Where it is `t` (0 to 1) into its flight.
func position_at(t: float) -> Vector3:
	return start.lerp(landing, t) + Vector3.UP * arc_height * 4.0 * t * (1.0 - t)


## Lands at `point` (global): blasts there and disappears. A `PlacedCharge` stays instead.
func _land(point: Vector3) -> void:
	Blast.explode(get_parent(), point, blast_radius, hit, blast_sound, _direct)
	queue_free()


## Moves to `target` unless something is in the way; then it lands there. Returns whether it
## landed.
func _move_to(target: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var skip: Array[RID] = exclude.duplicate()
	for _i: int in 8:
		var query := PhysicsRayQueryParameters3D.create(
			global_position, target, PhysicsLayers.SHOTS
		)
		query.exclude = skip
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			break
		var collider: Object = result["collider"]
		if collider is Player or (through_aliens and collider is Alien):
			skip.append((collider as CollisionObject3D).get_rid())
			continue
		if WeaponTarget.is_target(collider):
			_direct = collider as Node3D
		# Back off the surface a little, so the blast isn't inside it.
		var at: Vector3 = result["position"]
		var normal: Vector3 = result["normal"]
		global_position = at + normal * 0.2
		_landed = true
		_land(global_position)
		return true
	global_position = target
	return false
