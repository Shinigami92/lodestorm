extends GutTest

const NEST_SCENE: PackedScene = preload("res://game/aliens/nest/alien_nest.tscn")
const TEST_MAP := preload("res://tests/support/test_map.gd")

var _map: Node3D
var _mission: Mission
var _player: Player
var _ship: Ship
var _nest: AlienNest


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_mission = _map.get_node("Mission") as Mission
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	# The location's own nests would get in the way.
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		nest.queue_free()
	_nest = NEST_SCENE.instantiate() as AlienNest
	_nest.settings = _nest.settings.duplicate() as AlienNestSettings
	_nest.position = _ship.to_global(Vector3(55.0, 0.0, 0.0))
	_map.add_child(_nest)
	watch_signals(_nest)
	await wait_physics_frames(2)


func test_guards_hatch_around_the_nest() -> void:
	var aliens: Array[Alien] = _aliens()
	assert_eq(aliens.size(), _nest.settings.guards)
	for alien: Alien in aliens:
		assert_eq(alien.role, Alien.Role.GUARD)
		var offset: Vector3 = alien.global_position - _nest.global_position
		assert_almost_eq(Vector2(offset.x, offset.z).length(), _nest.settings.hatch_radius, 0.3)


func test_no_hunters_before_the_mission_starts() -> void:
	_set_interval(0.1)
	await _wait_physics(0.5)
	assert_eq(_nest.get_hunters().size(), 0)


func test_hunters_hatch_while_the_mission_runs() -> void:
	_set_interval(0.2)
	await _start_mission()
	assert_eq(_nest.get_hunters().size(), 0, "not before the first interval")
	await _wait_physics(0.4)
	assert_eq(_nest.get_hunters().size(), 1)
	assert_signal_emitted(_nest, "hatched")


func test_hunters_go_for_players_far_away() -> void:
	await _start_mission()
	var hunter: Alien = _nest.hatch(Alien.Role.HUNTER)
	await wait_physics_frames(2)
	var offset: Vector3 = _player.global_position - hunter.global_position
	assert_gt(Vector2(offset.x, offset.z).length(), hunter.strain.chase_range)
	assert_eq(hunter.target, _player)
	for alien: Alien in _aliens():
		if alien.role == Alien.Role.GUARD:
			assert_null(alien.target, "guards wait")


func test_hunters_find_their_way_around_the_nest() -> void:
	# A nest of the location itself: only those are part of its navigation mesh.
	_mission.reset_location()
	var nest: AlienNest = _mission.location.get_node("AlienNests/South") as AlienNest
	await _start_mission()
	var hunter: Alien = nest.hatch(Alien.Role.HUNTER)
	# Right behind the nest, seen from the player.
	var away: Vector3 = nest.global_position - _player.global_position
	away.y = 0.0
	hunter.global_position = nest.global_position + away.normalized() * 2.5
	hunter.reset_physics_interpolation()
	var start: float = _player.global_position.distance_to(hunter.global_position)
	await _wait_physics(3.0)
	var distance: float = _player.global_position.distance_to(hunter.global_position)
	assert_lt(distance, start - 8.0, "got past the nest")


func test_hunters_are_capped_and_replaced_an_interval_after_a_kill() -> void:
	_set_interval(0.1)
	_nest.settings.max_hunters_start = 2
	await _start_mission()
	await _wait_physics(0.6)
	assert_eq(_nest.get_hunters().size(), 2)
	_nest.get_hunters()[0].take_damage(1000.0)
	assert_eq(_nest.get_hunters().size(), 1)
	await wait_physics_frames(2)
	assert_eq(_nest.get_hunters().size(), 1, "not right away")
	await _wait_physics(0.2)
	assert_eq(_nest.get_hunters().size(), 2)


func test_nests_wait_while_the_living_aliens_reach_the_cap() -> void:
	_set_interval(0.1)
	_nest.settings.max_hunters_start = 4
	_nest.settings.max_aliens = Alien.living_load(get_tree()) + 1.0
	await _start_mission()
	await _wait_physics(0.6)
	assert_eq(_nest.get_hunters().size(), 1, "up to the cap")
	assert_true(_nest.is_full())
	_nest.settings.max_aliens += 1.0
	await _wait_physics(0.3)
	assert_eq(_nest.get_hunters().size(), 2, "goes on below it")


func test_raiders_only_hatch_while_a_miner_works() -> void:
	_set_raider_interval(0.1)
	await _start_mission()
	await _wait_physics(0.4)
	assert_eq(_nest.get_raiders().size(), 0, "no miner yet")
	var miner: Miner = _place_miner()
	await _wait_physics(0.05)
	assert_eq(_nest.get_raiders().size(), 0, "a full interval after the miner")
	await _wait_physics(0.2)
	assert_eq(_nest.get_raiders().size(), 1)
	miner.take_damage(miner.health)
	_nest.get_raiders()[0].take_damage(1000.0)
	await _wait_physics(0.4)
	assert_eq(_nest.get_raiders().size(), 0, "not while every miner is broken")


func test_raiders_go_for_miners() -> void:
	var miner: Miner = _place_miner()
	await _start_mission()
	var raider: Alien = _nest.hatch(Alien.Role.RAIDER)
	await wait_physics_frames(2)
	assert_eq(raider.target, miner)
	assert_eq(_nest.get_raiders(), [raider])
	assert_eq(_nest.get_hunters().size(), 0)


func test_raider_escalation() -> void:
	var settings: AlienNestSettings = _nest.settings
	assert_eq(_nest.raider_interval(0.0), settings.raider_interval_start)
	assert_eq(_nest.raider_interval(1.0), settings.raider_interval_end)
	assert_eq(_nest.max_raiders(0.0), settings.max_raiders_start)
	assert_eq(_nest.max_raiders(1.0), settings.max_raiders_end)


func test_escalation_follows_mission_progress() -> void:
	var settings: AlienNestSettings = _nest.settings
	assert_eq(_nest.escalation(), 0.0)
	assert_eq(_nest.hunter_interval(0.0), settings.hunter_interval_start)
	assert_eq(_nest.hunter_interval(1.0), settings.hunter_interval_end)
	assert_eq(_nest.max_hunters(0.0), settings.max_hunters_start)
	assert_eq(_nest.max_hunters(1.0), settings.max_hunters_end)
	await _start_mission()
	_mission.time_left = _mission.settings.duration * 0.25
	assert_almost_eq(_nest.escalation(), 0.75, 0.01)
	_mission.time_left = 0.0
	await wait_physics_frames(2)
	assert_eq(_mission.state, Mission.State.STORM)
	assert_eq(_nest.escalation(), 1.0)


func test_test_location_has_nests() -> void:
	var location: Node = _mission.location
	var nests: Array[Node] = get_tree().get_nodes_in_group(AlienNest.GROUP).filter(
		location.is_ancestor_of
	)
	assert_eq(nests.size(), 0, "freed in before_each")
	_mission.reset_location()
	await wait_physics_frames(2)
	nests = get_tree().get_nodes_in_group(AlienNest.GROUP).filter(_mission.location.is_ancestor_of)
	assert_gt(nests.size(), 0)


## Opens the ramp and puts the player outside, which starts the mission.
func _start_mission() -> void:
	_mission.state = Mission.State.OPEN
	_player.global_position = _ship.to_global(Vector3(22.0, 0.0, 0.0))
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_mission.state, Mission.State.RUNNING)


func _set_interval(seconds: float) -> void:
	_nest.settings.hunter_interval_start = seconds
	_nest.hunter_cooldown = seconds


func _set_raider_interval(seconds: float) -> void:
	_nest.settings.raider_interval_start = seconds
	_nest.raider_cooldown = seconds


## A miner on an ore node of the location (far from the nest, nobody repairs it).
func _place_miner() -> Miner:
	var node: OreNode = _mission.location.get_node("OreNodes/KyriteA") as OreNode
	return node.place_miner(_player.miner_scene)


func _aliens() -> Array[Alien]:
	var aliens: Array[Alien] = []
	aliens.assign(get_tree().get_nodes_in_group(Alien.GROUP).filter(_nest.is_ancestor_of))
	return aliens


## Waits `seconds` of physics time: on a busy machine it falls behind the wall clock that
## `wait_seconds` counts.
func _wait_physics(seconds: float) -> void:
	await wait_physics_frames(roundi(seconds * Engine.physics_ticks_per_second))
