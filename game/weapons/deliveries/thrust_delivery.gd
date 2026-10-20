class_name ThrustDelivery
extends WeaponDelivery
## A thrust straight ahead (Auger): every alien in a narrow line along the attack (the aim, or the
## direction to the locked target) up to its reach takes a hit; rock and a nest stop it (the nest
## takes the hit). It latches on to the first alien or nest it hit (`Weapon.latched`): while its
## trigger is held on (`DrillTrigger`), every attack drills into that one at `drill_rate`, each hit
## a share of a thrust's and harder the longer it stays on, up to `ramp` times after `ramp_time`
## seconds (quicker with the MK level of the weapon's ramp), so armor takes less off; the drill
## lets go when its target dies or gets out of reach. The bit spins (`Weapon.wind`, see
## `DrillTrigger`): full speed with a thrust, and while drilling the faster the more it ramped up.
## The holder's arms thrust (`Weapon.motion_started`) within `stroke` seconds.
## A thrust that hits plays `hit_sound`. All values TBD (playtest).

## How far to either side of an alien's center the line still hits it (its body, m).
const BODY: float = 0.35
## How fast the bit spins while drilling, from no ramp to a full one (`Weapon.wind`).
const DRILL_SPIN_MIN: float = 0.5

## How far the thrust reaches, from the holder (horizontally, m).
@export var reach: float = 4.0
## Seconds the holder's arms take to thrust out.
@export var stroke: float = 0.2
## Width of its line (m).
@export var width: float = 0.6
## Drilling hits per second.
@export var drill_rate: float = 10.0
## Share of a thrust's damage and stagger each drilling hit deals at first (before its ramp).
@export_range(0.0, 1.0) var drill_damage: float = 0.25
@export_range(0.0, 1.0) var drill_stagger: float = 0.1
## How many times the drill's damage once it stayed on its target for `ramp_time` seconds.
@export var ramp: float = 3.0
@export var ramp_time: float = 2.0
## Share of drilling hits that spray.
@export_range(0.0, 1.0) var drill_spray: float = 0.3

@export_group("Sounds")
## A thrust that hits something.
@export var hit_sound: Sound


func attack(weapon: Weapon) -> void:
	if is_instance_valid(weapon.latched):
		_drill(weapon)
	else:
		_thrust(weapon)


func interval(weapon: Weapon) -> float:
	if is_instance_valid(weapon.latched):
		return 1.0 / drill_rate
	return super(weapon)


## How far the drill's ramp has gone on its target, 0 to 1.
func ramped(weapon: Weapon) -> float:
	var seconds: float = ramp_time / weapon.multiplier(WeaponPart.Stat.RAMP)
	return clampf(weapon.latched_for / maxf(seconds, 0.01), 0.0, 1.0)


func _thrust(weapon: Weapon) -> void:
	var holder: CollisionObject3D = weapon.holder
	var from: Vector3 = holder.global_position
	var direction: Vector3 = facing(weapon)
	var aliens: Array[Alien] = hittable_aliens(weapon)
	var exclude: Array[RID] = [holder.get_rid()]
	for alien: Alien in aliens:
		exclude.append(alien.get_rid())
	var space: PhysicsDirectSpaceState3D = weapon.get_world_3d().direct_space_state
	var length: float = clear_distance(space, from + Vector3.UP, direction, reach, exclude)
	var hits: Array[Alien] = []
	for alien: Alien in aliens:
		var offset: Vector3 = alien.global_position - from
		var ahead: float = ahead_of(offset, direction)
		if ahead < 0.0 or ahead > length + BODY or absf(offset.y) > reach:
			continue
		if aside_of(offset, direction) <= width * 0.5 + BODY:
			hits.append(alien)
	hits.sort_custom(
		func(a: Alien, b: Alien) -> bool:
			return (
				from.distance_squared_to(a.global_position)
				< from.distance_squared_to(b.global_position)
			)
	)
	var first: Node3D = hits[0] if not hits.is_empty() else null
	for alien: Alien in hits:
		_hit(weapon, alien, direction).land_on(alien)
	var nest: Destructible = _nest_in_line(weapon, from, direction, length)
	if nest:
		_hit(weapon, nest, direction).land_on(nest)
		if not first or _flat_distance(from, nest) < _flat_distance(from, first):
			first = nest
	if first:
		weapon.play(hit_sound)
	weapon.latch(first)
	weapon.wind = 1.0
	weapon.motion_started.emit(Weapon.Motion.THRUST, stroke)
	weapon.swung.emit(hits)


## Drills into the latched alien or nest, or lets go of it once it's dead or out of reach.
func _drill(weapon: Weapon) -> void:
	var target: Node3D = weapon.latched
	if not _can_drill(weapon, target):
		weapon.latch(null)
		return
	weapon.latched_for += 1.0 / drill_rate
	var share: float = ramped(weapon)
	weapon.wind = lerpf(DRILL_SPIN_MIN, 1.0, share)
	var direction: Vector3 = target.global_position - weapon.holder.global_position
	direction.y = 0.0
	if direction.length() < 0.01:
		direction = weapon.aim_direction
	var hit: Hit = _hit(weapon, target, direction.normalized())
	var factor: float = lerpf(1.0, ramp, share)
	hit.damage *= drill_damage * factor
	hit.stagger *= drill_stagger * factor
	hit.push = 0.0
	hit.spray = randf() < drill_spray
	hit.land_on(target)


## Whether `target` is still there to drill: alive, hittable and within reach (a nest's edge).
func _can_drill(weapon: Weapon, target: Node3D) -> bool:
	if not target.is_inside_tree():
		return false
	var edge: float = 0.0
	if target is Alien:
		if not (target as Alien).is_hittable():
			return false
		edge = BODY
	elif target is Destructible:
		if not (target as Destructible).is_hittable():
			return false
		edge = (target as Destructible).radius()
	return _flat_distance(weapon.holder.global_position, target) <= reach + edge


## A hit on `target` along `direction`, landing at its body facing the holder.
func _hit(weapon: Weapon, target: Node3D, direction: Vector3) -> Hit:
	var edge: float = BODY
	var aim: Vector3 = target.global_position
	if target is Alien:
		aim = (target as Alien).get_aim_point()
	elif target is Destructible:
		aim = (target as Destructible).get_aim_point()
		edge = (target as Destructible).radius()
	return weapon.make_hit(direction, aim - direction * edge)


## The nearest nest whose edge is in the line from `from` along `direction` up to `length` m.
func _nest_in_line(
	weapon: Weapon, from: Vector3, direction: Vector3, length: float
) -> Destructible:
	var nearest: Destructible = null
	for node: Node in weapon.get_tree().get_nodes_in_group(Destructible.GROUP):
		var body := node as Destructible
		if not body.is_hittable():
			continue
		var offset: Vector3 = body.global_position - from
		var edge: float = body.radius()
		var ahead: float = ahead_of(offset, direction)
		if ahead < -edge or ahead - edge > length + 0.1:
			continue
		if aside_of(offset, direction) > width * 0.5 + edge:
			continue
		if not nearest or _flat_distance(from, body) < _flat_distance(from, nearest):
			nearest = body
	return nearest


static func _flat_distance(from: Vector3, target: Node3D) -> float:
	var offset: Vector3 = target.global_position - from
	return Vector2(offset.x, offset.z).length()
