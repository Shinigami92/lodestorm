@abstract class_name WeaponDelivery
extends Resource
## How a weapon's attack reaches its targets (see `WeaponType.delivery`): projectiles
## (`ProjectileDelivery`), a lobbed shell blasting where it lands (`LobDelivery`), a placed charge
## (`ChargeDelivery`), a gravity well (`WellDelivery`), a flame's cone (`ConeDelivery`), a beam
## (`BeamDelivery`), lightning jumping from alien to alien (`ChainDelivery`) or a swing
## (`SwingDelivery`) so far; thrusts, held tools and blocks are planned (see
## docs/planned/weapons.md). The weapon's effects make each hit (`Weapon.make_hit`). All values TBD
## (playtest).

## Performs one attack of `weapon`, along its aim direction or at its locked target.
@abstract func attack(weapon: Weapon) -> void


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
