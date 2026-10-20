class_name PunchDelivery
extends WeaponDelivery
## A punch (Clout): only the nearest alien within reach and the punch's arc (around the aim, or the
## direction to the locked target) with nothing solid in between takes the hit, or a nest whose
## edge is nearer; it's a fist. The hit travels along the attack, so a throw (`ThrowEffect`) goes
## where the holder aims. The holder's arms punch (`Weapon.motion_started`) within `stroke`
## seconds, and it emits `Weapon.swung`. A punch that lands plays `hit_sound`. All values TBD
## (playtest).

## How far a punch reaches, from the holder to an alien's center or a nest's edge (horizontally, m).
@export var reach: float = 2.2
## Width of the punch's arc around the attack direction, in degrees.
@export var arc: float = 60.0
## Seconds the holder's arms take to punch out.
@export var stroke: float = 0.15

@export_group("Sounds")
## A punch that lands.
@export var hit_sound: Sound


func attack(weapon: Weapon) -> void:
	var direction: Vector3 = facing(weapon)
	weapon.motion_started.emit(Weapon.Motion.PUNCH, stroke)
	var target: Node3D = nearest(weapon, direction)
	var hits: Array[Alien] = []
	if target:
		var edge: float = 0.3
		var aim: Vector3 = target.global_position
		if target is Alien:
			aim = (target as Alien).get_aim_point()
			hits.append(target as Alien)
		elif target is Destructible:
			aim = (target as Destructible).get_aim_point()
			edge = (target as Destructible).radius()
		weapon.make_hit(direction, aim - direction * edge).land_on(target)
		weapon.play(hit_sound)
	weapon.swung.emit(hits)


## The alien or nest a punch of `weapon` along `direction` lands on: the nearest one within reach
## and its arc, with nothing solid in between; null if none.
func nearest(weapon: Weapon, direction: Vector3) -> Node3D:
	var from: Vector3 = weapon.holder.global_position
	var half_arc: float = deg_to_rad(arc) * 0.5
	var aliens: Array[Alien] = hittable_aliens(weapon)
	var exclude: Array[RID] = [weapon.holder.get_rid()]
	var space: PhysicsDirectSpaceState3D = weapon.get_world_3d().direct_space_state
	var best: Node3D = null
	var best_distance: float = INF
	for alien: Alien in aliens:
		var offset: Vector3 = alien.global_position - from
		if absf(offset.y) > reach:
			continue
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > reach or distance >= best_distance:
			continue
		if distance > 0.01 and offset.angle_to(direction) > half_arc:
			continue
		if is_clear(space, from + Vector3.UP, alien.get_aim_point(), exclude):
			best = alien
			best_distance = distance
	for node: Node in weapon.get_tree().get_nodes_in_group(Destructible.GROUP):
		var body := node as Destructible
		if not body.is_hittable():
			continue
		var offset: Vector3 = body.global_position - from
		if absf(body.get_aim_point().y - from.y) > reach + body.aim_height:
			continue
		offset.y = 0.0
		var distance: float = offset.length() - body.radius()
		if distance > reach or distance >= best_distance:
			continue
		if distance <= 0.0 or offset.angle_to(direction) <= half_arc:
			best = body
			best_distance = distance
	return best
