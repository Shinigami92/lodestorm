class_name SwingDelivery
extends WeaponDelivery
## Swings at everything in front of the holder: every alien within reach and the swing's arc
## (around the aim direction, or the direction to the locked target; wider with the MK level of
## the weapon's arc) takes a hit, unless something solid is in the way, and so does a destructible
## (a nest) whose edge is within reach and the arc. The weapon's model moves as its `stroke` says
## (a stand-in for a swing animation), and it emits `Weapon.swung`. A swing that hits something
## plays `hit_sound`. A saw (Jag) doesn't stroke: it hits many times a second, only some of them
## spraying.
## A chain (`combo`, Riven) counts the swings made in a row, each within `combo_gap` of the last
## (`Weapon.chain`): they sweep one way, then back, and the last one lunges: the holder darts along
## the attack (farther with the MK level of the weapon's lunge; rock and the first alien in the way
## stop it short), and everything along its path takes `lunge_power` times a swing's hit. All
## values TBD (playtest).

## How the model moves with a swing: across the arc (`Weapon.sweep`), an overhead blow
## (`Weapon.chop`), or not at all (a saw's blade spins instead).
enum Stroke { SWEEP, OVERHEAD, NONE }

## Share of the time between swings the stroke takes.
const SWEEP_SHARE: float = 0.6
## How far short of rock and of the first alien in its way a lunge stops (m), and how high above
## the holder's feet it looks for rock.
const LUNGE_STOP: float = 0.9
const LUNGE_HEIGHT: float = 1.0
## How far the model thrusts forward with a lunge (m).
const LUNGE_THRUST: float = 0.5

## How far a swing reaches, from the holder to an alien's center (horizontally, in m).
@export var reach: float = 2.5
## Width of the swing around the attack direction at MK1, in degrees.
@export var arc: float = 120.0
@export var stroke: Stroke = Stroke.SWEEP
## Share of the hits that spray ichor or sparks (a saw hits ten times a second).
@export_range(0.0, 1.0) var spray_share: float = 1.0

@export_group("Chain")
## Swings in a chain, the last one lunging; below 2: no chain.
@export var combo: int = 0
## Seconds between two swings of a chain at most; a longer pause starts it over.
@export var combo_gap: float = 0.6
## How far the lunge goes at MK1 (m) and in how many seconds.
@export var lunge: float = 2.5
@export var lunge_time: float = 0.15
## How far to either side of the lunge's path it hits (m).
@export var lunge_width: float = 1.0
## How many times a swing's hit each of the lunge's hits is.
@export var lunge_power: float = 2.0

@export_group("Sounds")
## A swing that hits something.
@export var hit_sound: Sound
## A chain's lunge.
@export var lunge_sound: Sound


func attack(weapon: Weapon) -> void:
	var direction: Vector3 = facing(weapon)
	var aliens: Array[Alien] = hittable_aliens(weapon)
	var exclude: Array[RID] = [weapon.holder.get_rid()]
	for alien: Alien in aliens:
		exclude.append(alien.get_rid())
	if combo > 1:
		var goes_on: bool = weapon.since_attack <= combo_gap and weapon.chain < combo
		weapon.chain = weapon.chain + 1 if goes_on else 1
		if weapon.chain >= combo:
			_lunge(weapon, direction, aliens, exclude)
			return
	var half_arc: float = arc_of(weapon) * 0.5
	var hits: Array[Alien] = []
	for alien: Alien in aliens:
		if _in_swing(weapon, alien, direction, half_arc, exclude):
			hits.append(alien)
	var struck: bool = _strike(weapon, hits, direction)
	for node: Node in weapon.get_tree().get_nodes_in_group(Destructible.GROUP):
		var body := node as Destructible
		if body.is_hittable() and _reaches(weapon.holder, body, direction, half_arc):
			_strike_body(weapon, body, direction)
			struck = true
	if struck:
		weapon.play(hit_sound)
	var duration: float = SWEEP_SHARE / weapon.attack_rate()
	match stroke:
		Stroke.SWEEP:
			var back: bool = combo > 1 and weapon.chain % 2 == 0
			weapon.sweep(half_arc * (-2.0 if back else 2.0), duration)
		Stroke.OVERHEAD:
			weapon.chop(half_arc * 2.0, duration)
	weapon.swung.emit(hits)


## The width of `weapon`'s swing with its MK level, in radians.
func arc_of(weapon: Weapon) -> float:
	return deg_to_rad(arc * weapon.multiplier(WeaponPart.Stat.ARC))


## How far `weapon`'s lunge goes with its MK level, in m.
func lunge_of(weapon: Weapon) -> float:
	return lunge * weapon.multiplier(WeaponPart.Stat.LUNGE)


## The chain's last swing: the holder darts along `direction` (short of rock and the first alien
## in the way), hitting every alien and nest along the path harder.
func _lunge(weapon: Weapon, direction: Vector3, aliens: Array[Alien], exclude: Array[RID]) -> void:
	var holder: CollisionObject3D = weapon.holder
	var from: Vector3 = holder.global_position
	var distance: float = lunge_of(weapon)
	var space: PhysicsDirectSpaceState3D = weapon.get_world_3d().direct_space_state
	var eye: Vector3 = from + Vector3.UP * LUNGE_HEIGHT
	var clear: float = clear_distance(space, eye, direction, distance + LUNGE_STOP, exclude)
	distance = minf(distance, clear - LUNGE_STOP)
	for alien: Alien in aliens:
		var offset: Vector3 = alien.global_position - from
		var ahead: float = ahead_of(offset, direction)
		if ahead > 0.0 and aside_of(offset, direction) <= lunge_width and absf(offset.y) <= reach:
			distance = minf(distance, ahead - LUNGE_STOP)
	distance = maxf(distance, 0.0)
	weapon.power = lunge_power
	var hits: Array[Alien] = []
	for alien: Alien in aliens:
		var offset: Vector3 = alien.global_position - from
		var ahead: float = ahead_of(offset, direction)
		if ahead < 0.0 or ahead > distance + reach or absf(offset.y) > reach:
			continue
		if aside_of(offset, direction) <= lunge_width and _clear(weapon, alien, exclude):
			hits.append(alien)
	var struck: bool = _strike(weapon, hits, direction)
	for node: Node in weapon.get_tree().get_nodes_in_group(Destructible.GROUP):
		var body := node as Destructible
		if not body.is_hittable():
			continue
		var offset: Vector3 = body.global_position - from
		var ahead: float = ahead_of(offset, direction)
		var edge: float = body.radius()
		if ahead < -edge or ahead > distance + reach + edge:
			continue
		if aside_of(offset, direction) <= lunge_width + edge:
			_strike_body(weapon, body, direction)
			struck = true
	if struck:
		weapon.play(hit_sound)
	weapon.play(lunge_sound)
	if holder is Player:
		(holder as Player).suit_dash.lunge(direction, distance, lunge_time)
	weapon.thrust(LUNGE_THRUST, lunge_time * 2.0)
	weapon.swung.emit(hits)


## Hits each of `aliens`; returns whether there were any.
func _strike(weapon: Weapon, aliens: Array[Alien], direction: Vector3) -> bool:
	for alien: Alien in aliens:
		var away: Vector3 = alien.global_position - weapon.holder.global_position
		var point: Vector3 = alien.get_aim_point() - Vector3(away.x, 0.0, away.z).normalized() * 0.4
		var hit: Hit = weapon.make_hit(away if away.length() > 0.01 else direction, point)
		hit.spray = randf() < spray_share
		hit.land_on(alien)
	return not aliens.is_empty()


## Hits `body` (a nest) at its edge facing the holder.
func _strike_body(weapon: Weapon, body: Destructible, direction: Vector3) -> void:
	var away: Vector3 = body.global_position - weapon.holder.global_position
	away.y = 0.0
	var toward: Vector3 = away.normalized() if away.length() > 0.01 else direction
	var hit: Hit = weapon.make_hit(toward, body.get_aim_point() - toward * body.radius())
	hit.spray = randf() < spray_share
	hit.land_on(body)


## Whether `alien` is within reach and `half_arc` either side of `direction`, with nothing solid in
## between (other aliens don't block, a swing hits them all).
func _in_swing(
	weapon: Weapon, alien: Alien, direction: Vector3, half_arc: float, exclude: Array[RID]
) -> bool:
	var offset: Vector3 = alien.global_position - weapon.holder.global_position
	if absf(offset.y) > reach:
		return false
	offset.y = 0.0
	var distance: float = offset.length()
	if distance > reach:
		return false
	if distance > 0.01 and offset.angle_to(direction) > half_arc:
		return false
	return _clear(weapon, alien, exclude)


## Whether nothing solid is between the holder and `alien` (`exclude`: the holder and the aliens).
func _clear(weapon: Weapon, alien: Alien, exclude: Array[RID]) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		weapon.holder.global_position + Vector3.UP, alien.get_aim_point(), PhysicsLayers.SHOTS
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
