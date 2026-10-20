class_name SwingDelivery
extends WeaponDelivery
## Swings at everything in front of the holder: every alien within reach and the swing's arc
## (around the aim direction, or the direction to the locked target; wider with the MK level of
## the weapon's arc) takes a hit, unless something solid is in the way, and so does a destructible
## (a nest) whose edge is within reach and the arc. The weapon's model sweeps through the arc, a
## stand-in for a swing animation, and emits `Weapon.swung`. A swing that hits something plays
## `hit_sound`. All values TBD (playtest).

## Share of the time between swings the sweep takes.
const SWEEP_SHARE: float = 0.6

## How far a swing reaches, from the holder to an alien's center (horizontally, in m).
@export var reach: float = 2.5
## Width of the swing around the attack direction at MK1, in degrees.
@export var arc: float = 120.0

@export_group("Sounds")
## A swing that hits something.
@export var hit_sound: Sound


func attack(weapon: Weapon) -> void:
	var holder: CollisionObject3D = weapon.holder
	var direction: Vector3 = weapon.aim_direction
	if PlayerAim.is_lockable(weapon.aim_target):
		var to_target: Vector3 = weapon.aim_target.global_position - holder.global_position
		to_target.y = 0.0
		if to_target.length() > 0.01:
			direction = to_target.normalized()
	var half_arc: float = arc_of(weapon) * 0.5
	var aliens: Array[Alien] = []
	var exclude: Array[RID] = [holder.get_rid()]
	for node: Node in weapon.get_tree().get_nodes_in_group(Alien.GROUP):
		var alien := node as Alien
		if alien.is_hittable():
			aliens.append(alien)
			exclude.append(alien.get_rid())
	var hits: Array[Alien] = []
	for alien: Alien in aliens:
		if _in_swing(weapon, alien, direction, half_arc, exclude):
			hits.append(alien)
	for alien: Alien in hits:
		var away: Vector3 = alien.global_position - holder.global_position
		var point: Vector3 = alien.get_aim_point() - Vector3(away.x, 0.0, away.z).normalized() * 0.4
		var hit: Hit = weapon.make_hit(away if away.length() > 0.01 else direction, point)
		DamageNumber.show_hit(holder, alien, alien.take_hit(hit))
	var struck: bool = not hits.is_empty()
	for node: Node in weapon.get_tree().get_nodes_in_group(Destructible.GROUP):
		var body := node as Destructible
		if body.is_hittable() and _reaches(holder, body, direction, half_arc):
			struck = true
			var away: Vector3 = body.global_position - holder.global_position
			away.y = 0.0
			var along: Vector3 = away.normalized() if away.length() > 0.01 else direction
			var point: Vector3 = body.get_aim_point() - along * body.radius()
			DamageNumber.show_hit(holder, body, body.take_hit(weapon.make_hit(along, point)))
	if struck:
		weapon.play(hit_sound)
	weapon.sweep(half_arc * 2.0, SWEEP_SHARE / weapon.attack_rate())
	weapon.swung.emit(hits)


## The width of `weapon`'s swing with its MK level, in radians.
func arc_of(weapon: Weapon) -> float:
	return deg_to_rad(arc * weapon.multiplier(WeaponPart.Stat.ARC))


## Whether `alien` is within reach and `half_arc` either side of `direction`, with nothing solid in
## between (other aliens don't block, a swing hits them all).
func _in_swing(
	weapon: Weapon, alien: Alien, direction: Vector3, half_arc: float, exclude: Array[RID]
) -> bool:
	var holder: CollisionObject3D = weapon.holder
	var offset: Vector3 = alien.global_position - holder.global_position
	if absf(offset.y) > reach:
		return false
	offset.y = 0.0
	var distance: float = offset.length()
	if distance > reach:
		return false
	if distance > 0.01 and offset.angle_to(direction) > half_arc:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		holder.global_position + Vector3.UP, alien.get_aim_point(), PhysicsLayers.SHOTS
	)
	query.exclude = exclude
	return weapon.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Whether `body`'s edge is within reach and its middle within `half_arc` either side of
## `direction` (or the holder stands at it).
func _reaches(
	holder: CollisionObject3D, body: Destructible, direction: Vector3, half_arc: float
) -> bool:
	var offset: Vector3 = body.global_position - holder.global_position
	if absf(body.get_aim_point().y - holder.global_position.y) > reach + body.aim_height:
		return false
	offset.y = 0.0
	var distance: float = offset.length() - body.radius()
	if distance > reach:
		return false
	return distance <= 0.0 or offset.angle_to(direction) <= half_arc
