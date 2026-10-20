class_name ConeDelivery
extends WeaponDelivery
## Fills a cone in front of the holder with every attack (Scald's flame): every alien within reach
## and the cone's angle (around the aim direction, or the direction to the locked target) takes a
## hit, unless rock is between it and the muzzle (other aliens, players and miners don't shelter
## it), and so does a nest whose edge is within it. Only some of the hits spray (ten a second
## would fill the air). The weapon's `WeaponStream` (its child `Stream`) shows it. All values TBD
## (playtest).

## Aliens closer than this (m) are in the cone at any angle in front of the holder.
const POINT_BLANK: float = 1.2
## How far above or below the holder the cone reaches (m).
const HEIGHT: float = 2.5
## Share of hits that spray.
const SPRAY_SHARE: float = 0.3

## How far it reaches, from the holder to an alien's center (horizontally, in m).
@export var reach: float = 5.0
## Width of the cone around the attack direction, in degrees.
@export var angle: float = 40.0


func attack(weapon: Weapon) -> void:
	var holder: CollisionObject3D = weapon.holder
	var direction: Vector3 = _direction(weapon)
	var half: float = deg_to_rad(angle) * 0.5
	var space: PhysicsDirectSpaceState3D = weapon.get_world_3d().direct_space_state
	var from: Vector3 = weapon.get_muzzle().global_position
	var exclude: Array[RID] = [holder.get_rid()]
	for node: Node in weapon.get_tree().get_nodes_in_group(Alien.GROUP):
		var alien := node as Alien
		if (
			not alien.is_hittable()
			or not _within(holder, alien.global_position, 0.0, direction, half)
		):
			continue
		if not is_clear(space, from, alien.get_aim_point(), exclude):
			continue
		_land(weapon, alien, alien.get_aim_point(), direction)
	for node: Node in weapon.get_tree().get_nodes_in_group(Destructible.GROUP):
		var body := node as Destructible
		if (
			not body.is_hittable()
			or not _within(holder, body.global_position, body.radius(), direction, half)
		):
			continue
		var reach_point: Vector3 = _nearest_point(holder, body)
		var past: Array[RID] = exclude.duplicate()
		past.append(body.get_rid())
		if is_clear(space, from, reach_point, past):
			_land(weapon, body, reach_point, direction)
	var stream := weapon.get_node_or_null(^"Stream") as WeaponStream
	if stream:
		stream.fire(from + direction * reach)


## The direction it fills: the aim, or towards the locked target (horizontal).
func _direction(weapon: Weapon) -> Vector3:
	var direction: Vector3 = weapon.aim_direction
	if PlayerAim.is_lockable(weapon.aim_target):
		var to_target: Vector3 = weapon.aim_target.global_position - weapon.holder.global_position
		to_target.y = 0.0
		if to_target.length() > 0.01:
			direction = to_target.normalized()
	return direction


## Whether something at `at` with `radius` is within reach and `half` either side of `direction`.
func _within(holder: Node3D, at: Vector3, radius: float, direction: Vector3, half: float) -> bool:
	var offset: Vector3 = at - holder.global_position
	if absf(offset.y) > HEIGHT:
		return false
	offset.y = 0.0
	var distance: float = offset.length() - radius
	if distance > reach:
		return false
	if distance <= POINT_BLANK:
		return distance <= 0.0 or offset.angle_to(direction) <= PI * 0.5
	return offset.angle_to(direction) <= half


## The point of `body`'s edge nearest the holder, at its aim height.
func _nearest_point(holder: Node3D, body: Destructible) -> Vector3:
	var away: Vector3 = body.global_position - holder.global_position
	away.y = 0.0
	var along: Vector3 = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	return body.get_aim_point() - along * body.radius()


func _land(weapon: Weapon, target: Node3D, point: Vector3, direction: Vector3) -> void:
	var away: Vector3 = target.global_position - weapon.holder.global_position
	var hit: Hit = weapon.make_hit(away if away.length() > 0.01 else direction, point)
	hit.spray = randf() < SPRAY_SHARE
	hit.land_on(target)
