class_name AlienThrow
extends RefCounted
## An alien flying from a throw (`Alien.thrown`, see `ThrowEffect`: Clout's punch): it flies along
## the hit, staggered, through players, miners and aliens; every other alien close to its way takes
## a share of the hit and is knocked aside, and rock or a nest stops it with a hit on top. A throw
## shorter than `MIN_DISTANCE` (after the strain's knockback: the apex) doesn't make it fly.

## Shorter throws (m) don't make it fly; the hit only pushes.
const MIN_DISTANCE: float = 0.5
## Who is this much higher or lower than it isn't hit on its way (m).
const PASS_HEIGHT: float = 1.5
## A nest's edge this close stops it (m).
const NEST_REACH: float = 0.4
## How steep a surface it runs into counts as a wall (the normal's largest upward share).
const WALL_NORMAL_Y: float = 0.6

## The hit that threw it, its throw, and the horizontal unit vector it flies along.
var hit: Hit
var effect: ThrowEffect
var direction := Vector3.ZERO

## Meters it still flies.
var _left: float = 0.0
## The aliens and nests it hit on its way (and itself), and the bodies it passes through.
var _passed: Array[Node3D] = []
var _exceptions: Array[PhysicsBody3D] = []


## Whether it's flying.
func is_flying() -> bool:
	return _left > 0.0


## Throws `alien` by `by` (a hit with a throw). Returns whether it flies.
func start(alien: Alien, by: Hit) -> bool:
	var length: float = by.throw_distance * alien.strain.knockback
	if length < MIN_DISTANCE:
		return false
	_end(alien)
	hit = by
	effect = by.throw
	direction = by.direction
	_left = length
	_passed = [alien]
	alien.stagger_for(length / maxf(effect.speed, 0.01) + effect.landing_stagger)
	for node: Node in alien.get_tree().get_nodes_in_group(Player.GROUP):
		_except(alien, node as PhysicsBody3D)
	for node: Node in alien.get_tree().get_nodes_in_group(Miner.GROUP):
		_except(alien, node as PhysicsBody3D)
	# It flies through the other aliens, knocking them aside.
	for node: Node in alien.get_tree().get_nodes_in_group(Alien.GROUP):
		if node != alien:
			_except(alien, node as PhysicsBody3D)
	return true


## The horizontal velocity of `alien` this physics step (`delta` s): along the throw, hitting the
## aliens and nests close to its way.
func step(alien: Alien, delta: float) -> Vector3:
	var travel: float = minf(effect.speed * delta, _left)
	_left -= travel
	_hit_on_the_way(alien)
	if _left <= 0.0:
		_land(alien, false)
		return Vector3.ZERO
	return direction * travel / maxf(delta, 0.0001)


## After `alien` moved: whether it flew into rock (or something else solid), which stops it.
func check_impact(alien: Alien) -> void:
	if not is_flying():
		return
	for i: int in alien.get_slide_collision_count():
		var collision: KinematicCollision3D = alien.get_slide_collision(i)
		var body: Object = collision.get_collider()
		if body is Alien or body is Player or body is Miner:
			continue
		if collision.get_normal().y > WALL_NORMAL_Y:
			continue
		if body is Destructible and not _passed.has(body as Node3D):
			_pass_on(alien, body as Destructible)
		_land(alien, true)
		return


## Hits every alien close to its way that it didn't hit yet, and a nest it reaches (stopping it).
func _hit_on_the_way(alien: Alien) -> void:
	var at: Vector3 = alien.global_position
	for node: Node in alien.get_tree().get_nodes_in_group(Alien.GROUP):
		var other := node as Alien
		if _passed.has(other) or not other.is_hittable():
			continue
		var offset: Vector3 = other.global_position - at
		if absf(offset.y) > PASS_HEIGHT:
			continue
		offset.y = 0.0
		if offset.length() <= effect.path_width:
			_pass_on(alien, other)
	for node: Node in alien.get_tree().get_nodes_in_group(Destructible.GROUP):
		var body := node as Destructible
		if _passed.has(body) or not body.is_hittable():
			continue
		var offset: Vector3 = body.global_position - at
		offset.y = 0.0
		if offset.length() - body.radius() <= NEST_REACH:
			_pass_on(alien, body)
			_land(alien, true)
			return


## `target` (an alien or a nest) takes the passed share of the hit, an alien knocked aside.
func _pass_on(alien: Alien, target: Node3D) -> void:
	_passed.append(target)
	var offset: Vector3 = target.global_position - alien.global_position
	offset.y = 0.0
	var sideways: Vector3 = offset - direction * offset.dot(direction)
	if sideways.length() < 0.05:
		# Straight ahead: aside to either side.
		sideways = direction.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	var aside: Vector3 = sideways.normalized()
	var point: Vector3 = target.global_position + Vector3.UP * 0.6 - offset.normalized() * 0.3
	var share: float = hit.throw_passed
	# A push of p m/s fades over 1 / PUSH_DECAY s: it carries the alien p / PUSH_DECAY m.
	var passed := Hit.new(
		hit.damage * share,
		hit.stagger * share,
		effect.aside * Alien.PUSH_DECAY,
		aside if target is Alien else direction,
		point,
		hit.attacker,
		hit.weapon_type
	)
	passed.land_on(target)


## Ends the flight; flying into something (`crashed`) hits it harder and staggers it longer.
func _land(alien: Alien, crashed: bool) -> void:
	_left = 0.0
	_end(alien)
	alien.velocity = Vector3(0.0, alien.velocity.y, 0.0)
	if not crashed:
		Sfx.play_at(effect.land_sound, alien.global_position)
		return
	Sfx.play_at(effect.crash_sound, alien.global_position)
	var wall := Hit.new(
		hit.damage * effect.wall_share,
		0.0,
		0.0,
		direction,
		alien.get_aim_point() + direction * 0.3,
		hit.attacker,
		hit.weapon_type
	)
	wall.land_on(alien)
	if alien.dead:
		return
	var daze: float = effect.wall_stagger
	for attack: AlienAttack in alien.strain.attacks:
		if attack is AlienCharge and not (attack is AlienDive):
			daze = maxf(daze, (attack as AlienCharge).daze)
	alien.stagger_for(daze)


func _except(alien: Alien, body: PhysicsBody3D) -> void:
	alien.add_collision_exception_with(body)
	_exceptions.append(body)


## Players and miners block it again.
func _end(alien: Alien) -> void:
	for body: PhysicsBody3D in _exceptions:
		if is_instance_valid(body):
			alien.remove_collision_exception_with(body)
	_exceptions.clear()
