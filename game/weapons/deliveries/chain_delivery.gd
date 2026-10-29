class_name ChainDelivery
extends WeaponDelivery
## Lightning (Fulgen): every attack arcs from the muzzle to the locked target (an alien or a nest
## within `reach`), else to the nearest alien within `reach` and `angle` around the aim, fliers
## too, and jumps on from there to the nearest alien within `jump_reach` it hasn't hit yet, up to
## `jumps` times (more with the MK level of the weapon's jumps), each jump's hit `jump_share` of the
## one before (a locked nest takes the first arc and ends it). Rock stops an arc; aliens, players
## and miners don't. Hidden aliens (a stalker's cloak) aren't picked, like the target lock. With no
## alien to reach it strikes the ground `ground_reach` m along the aim, or what's in the way (a nest
## takes the hit). The weapon's `ChainArc` (its child `Arc`) shows it. All values TBD (playtest).

## How far above or below the holder it finds aliens (m): fliers are in reach.
const HEIGHT: float = 7.0
## Aliens closer than this (m) are in reach at any angle in front of the holder.
const POINT_BLANK: float = 1.2
## The ground strike looks for the ground this far above and below its end (m).
const GROUND_SEARCH: float = 3.0

## How far the first arc reaches, from the holder to an alien (horizontally, m).
@export var reach: float = 14.0
## Width of the cone around the aim it picks the first alien in, in degrees.
@export var angle: float = 60.0
## How many times it jumps on at MK1.
@export var jumps: int = 3
## How far it jumps from one alien to the next (m).
@export var jump_reach: float = 5.0
## Share of the hit before that each jump hits with.
@export var jump_share: float = 0.75
## How far along the aim it strikes the ground with no alien to reach (m).
@export var ground_reach: float = 8.0


func attack(weapon: Weapon) -> void:
	var from: Vector3 = weapon.get_muzzle().global_position
	var space: PhysicsDirectSpaceState3D = weapon.get_world_3d().direct_space_state
	var exclude: Array[RID] = [weapon.holder.get_rid()]
	var points: PackedVector3Array = [from]
	var target: Node3D = _first_target(weapon, from, space, exclude)
	if not target:
		points.append(_strike_ground(weapon, from, space, exclude))
	else:
		var struck: Array[Node3D] = []
		var share: float = 1.0
		var at: Vector3 = from
		var left: int = jumps_of(weapon)
		while target:
			var point: Vector3 = WeaponTarget.aim_point(target)
			_land(weapon, target, at, point, share)
			points.append(point)
			struck.append(target)
			# Only aliens pass it on (a nest takes the rest).
			if left <= 0 or target is not Alien:
				break
			left -= 1
			share *= jump_share
			at = point
			target = _next_jump(weapon, target as Alien, struck, space)
	var arc := weapon.get_node_or_null(^"Arc") as ChainArc
	if arc:
		arc.strike(points)


## How many times `weapon`'s lightning jumps on, with its MK level.
func jumps_of(weapon: Weapon) -> int:
	return maxi(0, roundi(jumps * weapon.multiplier(WeaponPart.Stat.JUMPS)))


## The locked target within reach, else the nearest alien in the cone with nothing solid in the way,
## or null.
func _first_target(
	weapon: Weapon, from: Vector3, space: PhysicsDirectSpaceState3D, exclude: Array[RID]
) -> Node3D:
	var holder: Node3D = weapon.holder
	var locked: Node3D = weapon.aim_target
	if PlayerAim.is_lockable(locked):
		var offset: Vector3 = locked.global_position - holder.global_position
		if Vector2(offset.x, offset.z).length() - WeaponTarget.edge(locked) <= reach:
			# Its own body doesn't stand in the way (an alien never does).
			var past: Array[RID] = exclude.duplicate()
			past.append((locked as CollisionObject3D).get_rid())
			if is_clear(space, from, WeaponTarget.aim_point(locked), past):
				return locked
	var direction: Vector3 = weapon.aim_direction
	var half: float = deg_to_rad(angle) * 0.5
	var nearest: Alien
	var nearest_distance: float = INF
	for node: Node in weapon.get_tree().get_nodes_in_group(Alien.GROUP):
		var alien := node as Alien
		if not PlayerAim.is_lockable(alien):
			continue
		var offset: Vector3 = alien.global_position - holder.global_position
		if absf(offset.y) > HEIGHT:
			continue
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > reach or distance >= nearest_distance:
			continue
		if distance > POINT_BLANK and offset.angle_to(direction) > half:
			continue
		if distance <= POINT_BLANK and distance > 0.01 and offset.angle_to(direction) > PI * 0.5:
			continue
		if is_clear(space, from, alien.get_aim_point(), exclude):
			nearest = alien
			nearest_distance = distance
	return nearest


## The nearest alien within `jump_reach` of `from` it hasn't `struck`, with nothing solid in the
## way, or null.
func _next_jump(
	weapon: Weapon, from: Alien, struck: Array[Node3D], space: PhysicsDirectSpaceState3D
) -> Alien:
	var start: Vector3 = from.get_aim_point()
	var exclude: Array[RID] = [weapon.holder.get_rid()]
	var nearest: Alien
	var nearest_distance: float = jump_reach
	for node: Node in weapon.get_tree().get_nodes_in_group(Alien.GROUP):
		var alien := node as Alien
		if struck.has(alien) or not PlayerAim.is_lockable(alien):
			continue
		var distance: float = start.distance_to(alien.get_aim_point())
		if distance > nearest_distance:
			continue
		if is_clear(space, start, alien.get_aim_point(), exclude):
			nearest = alien
			nearest_distance = distance
	return nearest


## Strikes along the aim with no alien to reach: what's in the way within `ground_reach` (a nest
## takes the hit), else the ground at its end. Returns where it struck.
func _strike_ground(
	weapon: Weapon, from: Vector3, space: PhysicsDirectSpaceState3D, exclude: Array[RID]
) -> Vector3:
	var direction: Vector3 = weapon.shot_direction()
	var end: Vector3 = from + direction * ground_reach
	var passed: Array[RID] = exclude.duplicate()
	for _i: int in 8:
		var query := PhysicsRayQueryParameters3D.create(from, end, PhysicsLayers.SHOTS)
		query.exclude = passed
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			break
		var collider: Object = result["collider"]
		if collider is Player or collider is Miner:
			passed.append((collider as CollisionObject3D).get_rid())
			continue
		var at: Vector3 = result["position"]
		if WeaponTarget.is_target(collider):
			_land(weapon, collider as Node3D, from, at, 1.0)
		DustPuff.spawn(weapon.holder.get_parent(), at, 0.4)
		return at
	var down := PhysicsRayQueryParameters3D.create(
		end + Vector3.UP * GROUND_SEARCH, end + Vector3.DOWN * GROUND_SEARCH, PhysicsLayers.WORLD
	)
	down.exclude = exclude
	var ground: Dictionary = space.intersect_ray(down)
	if not ground.is_empty() and not ground["collider"] is CharacterBody3D:
		end = ground["position"]
		DustPuff.spawn(weapon.holder.get_parent(), end, 0.4)
	return end


## Hits `target` at `point`, coming from `from`, with `share` of the weapon's hit.
func _land(weapon: Weapon, target: Node3D, from: Vector3, point: Vector3, share: float) -> void:
	var direction: Vector3 = point - from
	direction.y = 0.0
	if direction.length() < 0.01:
		direction = weapon.aim_direction
	var hit: Hit = weapon.make_hit(direction, point)
	hit.damage *= share
	hit.stagger *= share
	hit.land_on(target)
