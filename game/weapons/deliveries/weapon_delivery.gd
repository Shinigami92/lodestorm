@abstract class_name WeaponDelivery
extends Resource
## How a weapon's attack reaches its targets (see `WeaponType.delivery`): projectiles
## (`ProjectileDelivery`), a lobbed shell blasting where it lands (`LobDelivery`), a placed charge
## (`ChargeDelivery`), a gravity well (`WellDelivery`), a flame's cone (`ConeDelivery`), a beam
## (`BeamDelivery`), lightning jumping from alien to alien (`ChainDelivery`), a swing, also a saw's
## (`SwingDelivery`, also a shield's bash), a thrust and a drill (`ThrustDelivery`) and a punch
## (`PunchDelivery`). The weapon's effects make each hit (`Weapon.make_hit`). All values TBD
## (playtest).

## Performs one attack of `weapon`, along its aim direction or at its locked target.
@abstract func attack(weapon: Weapon) -> void


## Seconds from an attack of `weapon` until its next: one over its attack rate.
func interval(weapon: Weapon) -> float:
	return 1.0 / weapon.attack_rate()


## The horizontal unit vector a melee attack of `weapon` goes along: towards its locked target, else
## along its aim.
static func facing(weapon: Weapon) -> Vector3:
	if PlayerAim.is_lockable(weapon.aim_target):
		var to_target: Vector3 = weapon.aim_target.global_position - weapon.holder.global_position
		to_target.y = 0.0
		if to_target.length() > 0.01:
			return to_target.normalized()
	return weapon.aim_direction


## Every alien in `weapon`'s world that can be hit now.
static func hittable_aliens(weapon: Weapon) -> Array[Alien]:
	var aliens: Array[Alien] = []
	for node: Node in weapon.get_tree().get_nodes_in_group(Alien.GROUP):
		var alien := node as Alien
		if alien.is_hittable():
			aliens.append(alien)
	return aliens


## Whether nothing solid is between `from` and `to` in `space`: aliens, players and miners don't
## count (a flame and a beam reach past them), rock, props and nests do.
static func is_clear(
	space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]
) -> bool:
	var passed: Array[RID] = exclude.duplicate()
	for _i: int in 16:
		var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.SHOTS)
		query.exclude = passed
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			return true
		var collider: Object = result["collider"]
		if not (collider is Alien or collider is Player or collider is Miner):
			return false
		passed.append((collider as CollisionObject3D).get_rid())
	return true


## How far along `direction` from `from` up to `length` nothing solid is in `space`: aliens,
## players and miners don't count (`exclude` passes more), rock, props and nests do.
static func clear_distance(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	direction: Vector3,
	length: float,
	exclude: Array[RID]
) -> float:
	var passed: Array[RID] = exclude.duplicate()
	var to: Vector3 = from + direction * length
	for _i: int in 16:
		var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.SHOTS)
		query.exclude = passed
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			return length
		var collider: Object = result["collider"]
		if not (collider is Alien or collider is Player or collider is Miner):
			return from.distance_to(result["position"] as Vector3)
		passed.append((collider as CollisionObject3D).get_rid())
	return length


## How far `offset` goes along the horizontal unit vector `direction`.
static func ahead_of(offset: Vector3, direction: Vector3) -> float:
	return offset.x * direction.x + offset.z * direction.z


## How far `offset` lies to the side of a line along `direction` (horizontally).
static func aside_of(offset: Vector3, direction: Vector3) -> float:
	var flat := Vector3(offset.x, 0.0, offset.z)
	return (flat - direction * ahead_of(offset, direction)).length()
