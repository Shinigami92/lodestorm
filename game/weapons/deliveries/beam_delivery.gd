class_name BeamDelivery
extends WeaponDelivery
## A continuous beam from the muzzle along the aim (or straight at the locked target), up to its
## reach (farther with the MK level of the weapon's range): with every attack, what it touches
## takes a hit. Rock and nests stop it, and the first alien unless it `pierce`s them. A mending
## beam (`mends`, Kith) stops at the first teammate or miner too and heals or repairs them (the
## hit's `heal`, see `HealEffect`); any other beam passes them (no friendly fire). With a `ramp`
## (Zenith), an alien it stays on takes more, up to `ramp` times the damage after `ramp_time`
## seconds. The weapon's `WeaponBeam` (its child `Stream`) shows it. Only some of the hits spray
## (ten a second would fill the air). All values TBD (playtest).

## Share of hits that spray.
const SPRAY_SHARE: float = 0.3

## How far it reaches at MK1, in m.
@export var reach: float = 12.0
## Whether it goes on through every alien it hits.
@export var pierce: bool = false
## Whether it heals the first teammate and repairs the first miner it touches (and stops there).
@export var mends: bool = false
## How many times the damage an alien takes once the beam stayed on it for `ramp_time` seconds
## (1: always the same).
@export var ramp: float = 1.0
@export var ramp_time: float = 2.0


func attack(weapon: Weapon) -> void:
	var holder: CollisionObject3D = weapon.holder
	var beam := weapon.get_node_or_null(^"Stream") as WeaponBeam
	var from: Vector3 = weapon.get_muzzle().global_position
	var direction: Vector3 = weapon.shot_direction()
	var to: Vector3 = from + direction * reach_of(weapon)
	var space: PhysicsDirectSpaceState3D = weapon.get_world_3d().direct_space_state
	var exclude: Array[RID] = [holder.get_rid()]
	var end: Vector3 = to
	var heated: float = 0.0
	for _i: int in 16:
		var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.SHOTS)
		query.exclude = exclude
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			break
		var collider: Object = result["collider"]
		var at: Vector3 = result["position"]
		if collider is Alien:
			heated = maxf(heated, _hit_alien(weapon, collider as Alien, at, direction, beam))
			if pierce:
				exclude.append((collider as Alien).get_rid())
				continue
		elif WeaponTarget.is_target(collider):
			_hit(weapon, collider as Node3D, at, direction).land_on(collider as Node3D)
		elif collider is Player or collider is Miner:
			if not mends:
				exclude.append((collider as CollisionObject3D).get_rid())
				continue
			_mend(collider as Node3D, _hit(weapon, collider as Node3D, at, direction).heal)
		end = at
		break
	if beam:
		beam.heated = heated
		beam.fire(end)


## The reach of `weapon`'s beam with its MK level, in m.
func reach_of(weapon: Weapon) -> float:
	return reach * weapon.multiplier(WeaponPart.Stat.RANGE)


## Hits `alien` (harder the longer the beam stays on it, with a ramp). Returns how far the ramp
## has gone, 0 to 1.
func _hit_alien(
	weapon: Weapon, alien: Alien, at: Vector3, direction: Vector3, beam: WeaponBeam
) -> float:
	var hit: Hit = _hit(weapon, alien, at, direction)
	var heated: float = 0.0
	if ramp != 1.0 and beam:
		var stayed: float = beam.dwell(alien, 1.0 / weapon.attack_rate())
		heated = clampf(stayed / maxf(ramp_time, 0.01), 0.0, 1.0)
		var factor: float = lerpf(1.0, ramp, heated)
		hit.damage *= factor
		hit.stagger *= factor
	hit.land_on(alien)
	return heated


func _hit(weapon: Weapon, target: Node3D, at: Vector3, direction: Vector3) -> Hit:
	var away: Vector3 = target.global_position - weapon.holder.global_position
	var hit: Hit = weapon.make_hit(away if away.length() > 0.01 else direction, at)
	hit.spray = randf() < SPRAY_SHARE
	return hit


## Heals a teammate or repairs a miner by `amount`.
func _mend(target: Node3D, amount: float) -> void:
	if amount <= 0.0:
		return
	if target is Player:
		(target as Player).heal(amount)
	elif target is Miner:
		(target as Miner).repair(amount)
