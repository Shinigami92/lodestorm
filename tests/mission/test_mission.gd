extends GutTest

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")

var _map: Node3D
var _player: Player
var _mission: Mission
var _voyage: Voyage
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_mission = _map.get_node("Mission") as Mission
	_voyage = _map.get_node("Voyage") as Voyage
	_ship = _map.get_node("Ship") as Ship
	_ship.ramp_duration = 0.25
	await wait_physics_frames(2)
	TEST_MAP.pick_mission(_map)
	watch_signals(_mission)


func after_each() -> void:
	for action: StringName in [&"move_left", &"move_right", &"interact"]:
		Input.action_release(action)


func test_ramp_is_closed_by_default() -> void:
	await _move(_player, _inside())
	assert_true(_ship.is_ramp_up())
	assert_eq(_mission.state, Mission.State.CLOSED)
	Input.action_press(&"move_right")
	await wait_physics_frames(Engine.physics_ticks_per_second * 2)
	assert_true(_ship.is_aboard(_player), "the closed ramp blocks the door")
	assert_eq(_mission.state, Mission.State.CLOSED)


func test_button_next_to_door_lowers_ramp() -> void:
	await _move(_player, _ship.to_global(Vector3(13.5, 2.5, -3.0)))
	assert_eq(_player.interact_target, _ship.ramp_button)
	assert_true((_ship.ramp_button.get_node("Highlight") as Node3D).visible)
	Input.action_press(&"interact")
	await wait_physics_frames(2)
	Input.action_release(&"interact")
	assert_eq(_mission.state, Mission.State.OPEN)
	assert_signal_emit_count(_mission, "opened", 1)
	await _wait_for_ramp()
	assert_true(_ship.is_ramp_down())


func test_button_is_out_of_reach_from_the_middle_of_the_door() -> void:
	await _move(_player, _ship.to_global(Vector3(14.0, 2.5, 0.0)))
	assert_null(_player.interact_target)


func test_timer_waits_until_someone_steps_out() -> void:
	await _open()
	await wait_physics_frames(30)
	assert_eq(_mission.state, Mission.State.OPEN)
	assert_eq(_mission.time_left, _mission.duration())


func test_walking_out_starts_mission() -> void:
	await _move(_player, _inside())
	await _open()
	Input.action_press(&"move_right")
	await wait_physics_frames(Engine.physics_ticks_per_second * 2)
	assert_false(_ship.is_aboard(_player))
	assert_eq(_mission.state, Mission.State.RUNNING)
	assert_signal_emit_count(_mission, "started", 1)
	assert_lt(_mission.time_left, _mission.duration())


func test_button_raises_ramp_again_before_leaving() -> void:
	await _open()
	_ship.ramp_button.use(_player)
	assert_eq(_mission.state, Mission.State.CLOSED)
	await _wait_for_ramp()
	assert_true(_ship.is_ramp_up())


func test_button_is_disabled_while_someone_is_outside() -> void:
	await _open()
	await _move(_player, _outside())
	assert_false(_ship.ramp_button.enabled)
	_ship.ramp_button.use(_player)
	assert_eq(_mission.state, Mission.State.RUNNING)


func test_storm_hits_when_timer_runs_out() -> void:
	await _open()
	await _move(_player, _outside())
	_mission.time_left = 0.1
	await wait_physics_frames(roundi(Engine.physics_ticks_per_second * 0.5))
	assert_eq(_mission.time_left, 0.0)
	assert_eq(_mission.state, Mission.State.STORM)
	assert_signal_emit_count(_mission, "time_up", 1)


func test_walking_back_ends_mission_and_raises_ramp() -> void:
	await _open()
	await _move(_player, _outside())
	Input.action_press(&"move_left")
	await wait_physics_frames(Engine.physics_ticks_per_second * 2)
	Input.action_release(&"move_left")
	assert_true(_ship.is_aboard(_player))
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_signal_emit_count(_mission, "returned", 1)
	await _wait_for_ramp()
	assert_true(_ship.is_ramp_up())


func test_returning_stops_the_timer() -> void:
	await _open()
	await _move(_player, _outside())
	await _move(_player, _inside())
	var time_left: float = _mission.time_left
	await wait_physics_frames(10)
	assert_eq(_mission.time_left, time_left)


func test_returning_during_storm_still_counts() -> void:
	await _open()
	await _move(_player, _outside())
	_mission.time_left = 0.0
	await wait_physics_frames(2)
	assert_eq(_mission.state, Mission.State.STORM)
	await _move(_player, _inside())
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_signal_emit_count(_mission, "time_up", 1)


func test_waits_for_every_player() -> void:
	var other: Player = PLAYER_SCENE.instantiate() as Player
	_map.add_child(other)
	await _move(other, _inside())
	await _open()
	await _move(_player, _outside())
	await _move(other, _outside())
	await _move(_player, _inside())
	assert_eq(_mission.state, Mission.State.RUNNING, "one player is still outside")
	await _move(other, _inside())
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_signal_emit_count(_mission, "started", 1)
	assert_signal_emit_count(_mission, "returned", 1)


func test_next_mission_resets_timer_and_outside_world() -> void:
	await _open()
	var node: OreNode = _map.get_node("Location/OreNodes/KyriteA")
	await _move(_player, node.global_position + Vector3(1.5, 0.0, 0.0))
	assert_not_null(_player.place_miner())
	await _move(_player, _inside())
	assert_eq(_mission.state, Mission.State.RETURNED)
	var old_location: Node3D = _voyage.location
	await wait_physics_frames(2)
	assert_false(_ship.ramp_button.enabled, "the mission is done: pick the next one")

	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_physics_frames(2)
	assert_false(is_instance_valid(old_location), "the old outside world is gone")
	assert_eq(_mission.state, Mission.State.OPEN)
	assert_eq(_mission.time_left, _mission.duration())
	assert_eq(_voyage.location, _map.get_node("Location"))
	var fresh_node: OreNode = _map.get_node("Location/OreNodes/KyriteA")
	assert_true(fresh_node.is_free(), "no miner from the last run")
	await _move(_player, _outside())
	assert_eq(_mission.state, Mission.State.RUNNING)
	assert_signal_emit_count(_mission, "started", 2)


## Presses the ramp button and waits until the ramp is down.
func _open() -> void:
	_ship.ramp_button.use(_player)
	await _wait_for_ramp()


func _wait_for_ramp() -> void:
	await wait_physics_frames(ceili(_ship.ramp_duration * Engine.physics_ticks_per_second) + 2)


## Inside the ship, near the door.
func _inside() -> Vector3:
	return _ship.to_global(Vector3(10.0, 2.5, 0.0))


## On the ground right of the ramp.
func _outside() -> Vector3:
	return _ship.to_global(Vector3(22.0, 0.0, 0.0))


func _move(player: Player, target: Vector3) -> void:
	player.global_position = target
	player.reset_physics_interpolation()
	await wait_physics_frames(5)
