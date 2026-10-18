extends GutTest
## Armor, stagger, push and the hit feedback, and the swarmer's pounce.

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")

var _arena: Node3D
var _player: Player
var _alien: Alien


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	_arena.add_child(floor_body)
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	_alien = SWARMER.spawn()
	_alien.strain = SWARMER.duplicate() as AlienStrain
	_alien.position = Vector3(40.0, 0.0, 0.0)
	_arena.add_child(_alien)
	watch_signals(_alien)
	await wait_physics_frames(1)


func test_armor_takes_its_share_but_not_all() -> void:
	_alien.strain.armor = 8.0
	_alien.strain.max_health = 1000.0
	_alien.health = 1000.0
	assert_almost_eq(_alien.take_hit(_hit(30.0)), 22.0, 1e-4)
	assert_almost_eq(
		_alien.take_hit(_hit(10.0)), 10.0 * Alien.MIN_DAMAGE_SHARE, 1e-4, "always some gets through"
	)
	assert_almost_eq(_alien.health, 1000.0 - 22.0 - 2.5, 1e-4)
	assert_signal_emit_count(_alien, "hit_taken", 2)
	var armored: bool = get_signal_parameters(_alien, "hit_taken")[2]
	assert_true(armored)


func test_armor_on_the_front_only() -> void:
	_alien.strain.armor = 8.0
	_alien.strain.armor_arc = 120.0
	_alien.global_basis = Basis.IDENTITY
	# It faces -Z: a hit from the front travels along +Z.
	assert_almost_eq(_alien.take_hit(_hit(20.0, Vector3.BACK)), 12.0, 1e-4, "front")
	assert_almost_eq(_alien.take_hit(_hit(5.0, Vector3.FORWARD)), 5.0, 1e-4, "back")
	assert_almost_eq(_alien.take_hit(_hit(5.0, Vector3.RIGHT)), 5.0, 1e-4, "side")


func test_burning_ground_ignores_armor() -> void:
	_alien.strain.armor = 8.0
	_alien.take_damage(5.0)
	assert_almost_eq(_alien.health, _alien.max_health() - 5.0, 1e-4)


func test_hits_spray_ichor_and_sparks_off_armor() -> void:
	_alien.strain.max_health = 1000.0
	_alien.health = 1000.0
	_alien.take_hit(_hit(5.0))
	_alien.strain.armor = 1.0
	_alien.take_hit(_hit(5.0))
	var sprays: Array[HitSpray] = []
	for child: Node in _arena.get_children():
		if child is HitSpray:
			sprays.append(child as HitSpray)
	assert_eq(sprays.size(), 2)
	assert_eq(sprays[0].amount, HitSpray.ICHOR_AMOUNT, "ichor from flesh")
	assert_eq(sprays[1].amount, HitSpray.SPARK_AMOUNT, "sparks off armor")
	await _wait_physics(1.0)
	for spray: HitSpray in sprays:
		assert_false(is_instance_valid(spray), "gone when done")


func test_stagger_past_the_threshold_then_resets() -> void:
	_alien.strain.max_health = 1000.0
	_alien.health = 1000.0
	var threshold: float = _alien.strain.stagger_threshold
	_alien.take_hit(_hit(1.0, Vector3.LEFT, threshold * 0.45))
	_alien.take_hit(_hit(1.0, Vector3.LEFT, threshold * 0.45))
	assert_false(_alien.is_staggered())
	_alien.take_hit(_hit(1.0, Vector3.LEFT, threshold * 0.45))
	assert_true(_alien.is_staggered())
	assert_eq(_alien.stagger, 0.0, "a stagger empties the meter")
	_alien.take_hit(_hit(1.0, Vector3.LEFT, threshold * 0.9))
	assert_eq(_alien.stagger, 0.0, "hits while staggered don't fill it")
	await _wait_physics(_alien.strain.stagger_time + 0.05)
	assert_false(_alien.is_staggered())


func test_stagger_drains_within_a_second() -> void:
	_alien.strain.max_health = 1000.0
	_alien.health = 1000.0
	_alien.take_hit(_hit(1.0, Vector3.LEFT, _alien.strain.stagger_threshold * 0.9))
	await _wait_physics(Alien.STAGGER_DRAIN_TIME)
	assert_eq(_alien.stagger, 0.0)


func test_hits_push_it_back() -> void:
	_player.take_damage(_player.settings.max_health)
	_alien.strain.max_health = 1000.0
	_alien.health = 1000.0
	var start: Vector3 = _alien.global_position
	_alien.take_hit(_hit(1.0, Vector3.RIGHT, 0.0, 6.0))
	await _wait_physics(0.5)
	var moved: Vector3 = _alien.global_position - start
	assert_gt(moved.x, 0.4, "pushed along the hit")
	assert_lt(moved.x, 1.5, "a small push")


func test_pounce_hits_a_player_standing_still() -> void:
	var pounce: AlienPounce = _alien.strain.attacks[0]
	await _place_alien(4.5)
	await _wait_physics(0.1)
	assert_true(_alien.is_winding_up(), "crouches first")
	assert_eq(_player.health, _player.settings.max_health)
	await _wait_physics(pounce.wind_up + 0.4)
	assert_almost_eq(_player.health, _player.settings.max_health - pounce.damage, 1e-4)
	assert_lt(_distance(), 2.0, "leapt in")


func test_pounce_is_dodged_by_a_sidestep_and_leaves_an_opening() -> void:
	var pounce: AlienPounce = _alien.strain.attacks[0]
	await _place_alien(4.8)
	await _wait_physics(pounce.wind_up + 0.05)
	assert_false(_alien.is_winding_up(), "leaping")
	# Out of the way once it's in the air.
	_player.global_position = Vector3(0.0, 0.0, 4.0)
	_player.reset_physics_interpolation()
	await _wait_physics(0.4)
	assert_eq(_player.health, _player.settings.max_health, "dodged")
	assert_true(_alien.is_attacking(), "recovering")
	await _wait_physics(0.2)
	var ground_speed := Vector2(_alien.velocity.x, _alien.velocity.z).length()
	assert_lt(ground_speed, 0.5, "stands still meanwhile")


func test_stagger_breaks_off_the_pounce() -> void:
	await _place_alien(4.5)
	await _wait_physics(0.1)
	assert_true(_alien.is_winding_up())
	_alien.take_hit(_hit(1.0, Vector3.RIGHT, _alien.strain.stagger_threshold))
	assert_false(_alien.is_attacking())
	await _wait_physics(0.4)
	assert_eq(_player.health, _player.settings.max_health)


func test_raiders_without_miners_give_up_beyond_chase_range() -> void:
	_alien.role = Alien.Role.RAIDER
	await _place_alien(10.0)
	await wait_physics_frames(2)
	assert_eq(_alien.target, _player)
	_alien.global_position = Vector3(_alien.strain.chase_range + 1.0, 0.0, 0.0)
	await wait_physics_frames(2)
	assert_null(_alien.target)


func test_hunters_never_give_up_because_of_distance() -> void:
	_alien.role = Alien.Role.HUNTER
	await _place_alien(_alien.strain.chase_range + 10.0)
	await wait_physics_frames(2)
	assert_eq(_alien.target, _player)


func _hit(
	damage: float, along: Vector3 = Vector3.LEFT, stagger: float = 0.0, push: float = 0.0
) -> Hit:
	return Hit.new(damage, stagger, push, along, _alien.get_aim_point())


func _place_alien(distance: float) -> void:
	_alien.global_position = Vector3(distance, 0.0, 0.0)
	_alien.reset_physics_interpolation()
	await wait_physics_frames(1)


func _distance() -> float:
	var offset: Vector3 = _alien.global_position - _player.global_position
	return Vector2(offset.x, offset.z).length()


## Waits `seconds` of physics time: on a busy machine it falls behind the wall clock that
## `wait_seconds` counts.
func _wait_physics(seconds: float) -> void:
	await wait_physics_frames(roundi(seconds * Engine.physics_ticks_per_second))
