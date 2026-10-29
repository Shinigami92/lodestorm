extends GutTest
## `WeaponTarget`: an alien and a destructible (a nest's body) are hit, aimed at and measured
## alike; anything else isn't a target.

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const BODY_RADIUS: float = 1.5

var _arena: Node3D
var _alien: Alien
var _body: Destructible
var _plain: Node3D


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_alien = SWARMER.spawn()
	_alien.position = Vector3(0.0, 0.0, -4.0)
	_arena.add_child(_alien)
	_body = Destructible.new()
	_body.position = Vector3(4.0, 0.0, 0.0)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var cylinder := CylinderShape3D.new()
	cylinder.radius = BODY_RADIUS
	shape.shape = cylinder
	_body.add_child(shape)
	_arena.add_child(_body)
	_plain = Node3D.new()
	_plain.position = Vector3(-4.0, 1.0, 0.0)
	_arena.add_child(_plain)
	await wait_physics_frames(1)


func test_aliens_and_destructibles_are_targets() -> void:
	assert_true(WeaponTarget.is_target(_alien))
	assert_true(WeaponTarget.is_target(_body))
	assert_false(WeaponTarget.is_target(_plain))
	assert_false(WeaponTarget.is_target(null))
	assert_true(WeaponTarget.is_hittable(_alien))
	assert_true(WeaponTarget.is_hittable(_body))
	assert_false(WeaponTarget.is_hittable(_plain))
	assert_false(WeaponTarget.is_hittable(null))


func test_aim_point_and_edge() -> void:
	assert_eq(WeaponTarget.aim_point(_alien), _alien.get_aim_point())
	assert_eq(WeaponTarget.aim_point(_body), _body.get_aim_point())
	assert_eq(WeaponTarget.aim_point(_plain), _plain.global_position, "anything else: its origin")
	assert_eq(WeaponTarget.edge(_body, 0.4), BODY_RADIUS, "a destructible's shape")
	assert_eq(WeaponTarget.edge(_alien, 0.4), 0.4, "an alien's body, as the weapon measures it")
	assert_eq(WeaponTarget.edge(_alien), 0.0)


func test_hits_and_damage_land_on_either() -> void:
	var alien_health: float = _alien.health
	assert_gt(WeaponTarget.take_hit(_alien, _hit(_alien)), 0.0)
	assert_lt(_alien.health, alien_health)
	var body_health: float = _body.health
	assert_gt(WeaponTarget.take_hit(_body, _hit(_body)), 0.0)
	assert_lt(_body.health, body_health)
	assert_eq(WeaponTarget.take_hit(_plain, _hit(_plain)), 0.0, "not a target")
	assert_false(WeaponTarget.take_damage(_plain, 10.0))
	assert_true(WeaponTarget.take_damage(_body, _body.health + _body.armor + 1.0))
	assert_true(_body.dead)
	assert_false(WeaponTarget.is_hittable(_body), "destroyed")


func _hit(target: Node3D) -> Hit:
	return Hit.new(20.0, 0.0, 0.0, Vector3.FORWARD, WeaponTarget.aim_point(target))
