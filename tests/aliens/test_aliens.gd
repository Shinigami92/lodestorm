extends GutTest

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const MINER_SCENE: PackedScene = preload("res://game/mining/miner.tscn")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const PROJECTILE: PackedScene = preload("res://game/weapons/projectile.tscn")
const TEST_MAP := preload("res://tests/support/map_fixture.gd")

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
	_alien.position = Vector3(50.0, 0.0, 0.0)
	_arena.add_child(_alien)
	watch_signals(_alien)


func after_each() -> void:
	Alien.ai_on = true


## Aliens find their way however long it is: around the rock of a generated location the default
## search limit runs out (and Godot logs an error every frame).
func test_path_search_has_no_polygon_limit() -> void:
	var agent := _alien.get_node("NavigationAgent3D") as NavigationAgent3D
	assert_eq(agent.path_search_max_polygons, 0)


func test_waits_until_player_in_range() -> void:
	await _place_alien(_alien.strain.detection_range + 3.0)
	await wait_physics_frames(10)
	assert_null(_alien.target)
	assert_almost_eq(_distance(), _alien.strain.detection_range + 3.0, 0.01, "stays put")


func test_chases_player_in_range() -> void:
	var start: float = _alien.strain.detection_range - 4.0
	await _place_alien(start)
	await wait_physics_frames(30)
	assert_eq(_alien.target, _player)
	assert_lt(_distance(), start - 1.0, "comes closer")


func test_faces_where_it_runs() -> void:
	# Under a turned parent, like the aliens of a location turned on the map.
	_arena.rotation.y = PI * 0.25
	await _place_alien(_alien.strain.detection_range - 2.0)
	# Start the chase facing away, so it has to turn while it speeds up.
	_alien.global_basis = Basis(Vector3.UP, PI * 0.5)
	await wait_physics_frames(20)
	var ground_velocity := Vector3(_alien.velocity.x, 0.0, _alien.velocity.z)
	assert_gt(ground_velocity.length(), 1.0, "running")
	assert_gt(-_alien.global_basis.z.dot(ground_velocity.normalized()), 0.9, "head first")


func test_stops_in_reach_and_bites_at_its_rate() -> void:
	# Closer than the pounce starts.
	await _place_alien(2.0)
	var bite: AlienBite = _alien.strain.attacks[1]
	var max_health: float = _player.settings.max_health
	var seconds: float = 1.5
	await wait_physics_frames(ceili(seconds * Engine.physics_ticks_per_second))
	assert_lt(_distance(), bite.reach + 0.01)
	var attacks: int = roundi((max_health - _player.health) / bite.damage)
	assert_between(attacks, 1, ceili(seconds / bite.cooldown))
	assert_gt(_distance(), 0.8, "doesn't walk into the player")


func test_player_gets_away_beyond_chase_range() -> void:
	await _place_alien(_alien.strain.detection_range - 1.0)
	await wait_physics_frames(2)
	assert_eq(_alien.target, _player)
	_alien.global_position = Vector3(_alien.strain.chase_range - 1.0, 0.0, 0.0)
	await wait_physics_frames(2)
	assert_eq(_alien.target, _player, "still chased between detection and chase range")
	_alien.global_position = Vector3(_alien.strain.chase_range + 1.0, 0.0, 0.0)
	await wait_physics_frames(2)
	assert_null(_alien.target)


func test_ignores_dead_players() -> void:
	_player.take_damage(_player.settings.max_health)
	await _place_alien(3.0)
	await wait_physics_frames(10)
	assert_null(_alien.target)


func test_projectile_damages_alien() -> void:
	await _place_alien(8.0)
	var projectile := PROJECTILE.instantiate() as Projectile
	projectile.velocity = Vector3.RIGHT * 30.0
	projectile.max_distance = 25.0
	projectile.damage = 7.0
	_arena.add_child(projectile)
	projectile.global_position = Vector3(4.0, 1.1, 0.0)
	await wait_physics_frames(15)
	assert_false(is_instance_valid(projectile))
	assert_eq(_alien.health, _alien.max_health() - 7.0)


func test_projectile_does_not_damage_players() -> void:
	var projectile := PROJECTILE.instantiate() as Projectile
	projectile.velocity = Vector3.LEFT * 30.0
	projectile.max_distance = 25.0
	projectile.damage = 7.0
	_arena.add_child(projectile)
	projectile.global_position = Vector3(4.0, 1.1, 0.0)
	await wait_physics_frames(15)
	assert_false(is_instance_valid(projectile), "blocked by the player")
	assert_eq(_player.health, _player.settings.max_health)


func test_dies_at_zero_health_and_disappears() -> void:
	await _place_alien(30.0)
	_alien.take_damage(_alien.strain.max_health + 5.0)
	assert_true(_alien.dead)
	assert_eq(_alien.health, 0.0)
	assert_signal_emit_count(_alien, "died", 1)
	assert_false(_alien.is_in_group(Alien.GROUP))
	_alien.take_damage(5.0)
	assert_signal_emit_count(_alien, "died", 1)
	await wait_seconds(Alien.DEATH_DURATION + 0.1)
	assert_false(is_instance_valid(_alien))


func test_dead_alien_does_not_attack() -> void:
	_alien.take_damage(_alien.strain.max_health)
	await _place_alien(1.0)
	await wait_physics_frames(10)
	assert_eq(_player.health, _player.settings.max_health)


func test_without_its_ai_it_stands_still_and_breaks_off_its_attack() -> void:
	await _place_alien(2.0)
	await wait_physics_frames(5)
	assert_eq(_alien.target, _player)
	Alien.ai_on = false
	await wait_physics_frames(2)
	var health: float = _player.health
	var at: Vector3 = _alien.global_position
	await wait_physics_frames(60)
	assert_null(_alien.target)
	assert_false(_alien.is_attacking())
	assert_eq(_player.health, health, "no more bites")
	assert_almost_eq(_alien.global_position.distance_to(at), 0.0, 0.05, "stays put")
	_alien.take_damage(5.0)
	assert_eq(_alien.health, _alien.max_health() - 5.0, "can still be hurt")
	Alien.ai_on = true
	await wait_physics_frames(2)
	assert_eq(_alien.target, _player, "hunts again")


func test_no_hunting_aboard_the_ship() -> void:
	var map := TEST_MAP.instantiate() as Node3D
	add_child_autofree(map)
	var player: Player = map.get_node("Player") as Player
	var ship: Ship = map.get_node("Ship") as Ship
	_arena.queue_free()
	await wait_physics_frames(5)
	assert_true(ship.is_aboard(player), "the test map starts aboard")
	var alien := SWARMER.spawn()
	map.add_child(alien)
	alien.global_position = player.global_position + Vector3(2.0, 0.0, 0.0)
	await wait_physics_frames(30)
	assert_null(alien.target)
	assert_eq(player.health, player.settings.max_health)


func test_location_has_aliens_and_resets_them() -> void:
	var map := TEST_MAP.instantiate() as Node3D
	add_child_autofree(map)
	_arena.queue_free()
	await wait_physics_frames(2)
	assert_gt(_aliens_in(map.get_node("Location")), 0)
	for alien: Alien in get_tree().get_nodes_in_group(Alien.GROUP):
		alien.take_damage(alien.health)
	var mission: Mission = map.get_node("Mission") as Mission
	mission.reset_location()
	await wait_physics_frames(2)
	# Every nest's guards hatch again (packs picked anew, so not always as many).
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		if mission.location.is_ancestor_of(nest):
			assert_gt(_aliens_in(nest), 0, nest.name)


func test_raider_goes_for_a_miner_far_away_and_ignores_players() -> void:
	# Off to the side: the player doesn't stand in its way.
	var miner: Miner = _add_miner(Vector3(3.0, 0.0, -40.0))
	_alien.role = Alien.Role.RAIDER
	await _place_alien(3.0)
	var health: float = _player.health
	await wait_physics_frames(10)
	assert_eq(_alien.target, miner)
	await _wait_physics(1.0)
	assert_eq(_player.health, health, "walks past the player")


func test_raider_attacks_the_miner_until_it_breaks() -> void:
	var miner: Miner = _add_miner(Vector3(-10.0, 0.0, 0.0))
	miner.settings.max_health = (_alien.strain.attacks[1] as AlienBite).damage * 2.0
	miner.health = miner.settings.max_health
	_alien.role = Alien.Role.RAIDER
	await _place_alien(-13.0)
	await _wait_physics(2.0)
	assert_true(miner.broken)
	assert_eq(_alien.target, _player, "goes for players close by once no miner works")


func test_raider_lets_go_of_a_miner_picked_up() -> void:
	var miner: Miner = _add_miner(Vector3(3.0, 0.0, -40.0))
	_alien.role = Alien.Role.RAIDER
	await _place_alien(3.0)
	await wait_physics_frames(2)
	assert_eq(_alien.target, miner)
	miner.free()
	await wait_physics_frames(2)
	assert_true(_alien.target == null or is_instance_valid(_alien.target), "forgets it")


func test_others_ignore_miners() -> void:
	_add_miner(Vector3(-40.0, 0.0, 0.0))
	_alien.role = Alien.Role.HUNTER
	await _place_alien(30.0)
	await wait_physics_frames(2)
	assert_eq(_alien.target, _player)


## A miner of its own (no ore, no hose) at `at`.
func _add_miner(at: Vector3) -> Miner:
	var miner := MINER_SCENE.instantiate() as Miner
	miner.settings = miner.settings.duplicate() as MinerSettings
	miner.settings.hose_range = 0.0
	miner.settings.repair_range = 0.0
	miner.position = at
	_arena.add_child(miner)
	return miner


func _place_alien(distance: float) -> void:
	_alien.global_position = Vector3(distance, 0.0, 0.0)
	_alien.reset_physics_interpolation()
	await wait_physics_frames(1)


func _distance() -> float:
	var offset: Vector3 = _alien.global_position - _player.global_position
	return Vector2(offset.x, offset.z).length()


func _aliens_in(node: Node) -> int:
	return get_tree().get_nodes_in_group(Alien.GROUP).filter(node.is_ancestor_of).size()


## Waits `seconds` of physics time: on a busy machine it falls behind the wall clock that
## `wait_seconds` counts.
func _wait_physics(seconds: float) -> void:
	await wait_physics_frames(roundi(seconds * Engine.physics_ticks_per_second))
