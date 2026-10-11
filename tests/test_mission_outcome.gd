extends GutTest

const TEST_MAP: PackedScene = preload("res://scenes/maps/test_map.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const CYAN: OreType = preload("res://scenes/mining/ores/ore_cyan.tres")

var _map: Node3D
var _player: Player
var _mission: Mission
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_mission = _map.get_node("Mission") as Mission
	_ship = _map.get_node("Ship") as Ship
	_ship.ramp_duration = 0.25
	_mission.settings = _mission.settings.duplicate()
	_mission.settings.respawn_delay = 0.25
	watch_signals(_mission)
	await wait_physics_frames(2)


func after_each() -> void:
	for action: StringName in [&"move_left", &"move_right", &"interact"]:
		Input.action_release(action)


func test_storm_hurts_players_outside() -> void:
	await _open()
	await _move(_player, _outside())
	assert_eq(_player.health, _player.settings.max_health, "no damage before the storm")
	_mission.time_left = 0.0
	await wait_physics_frames(10)
	assert_lt(_player.health, _player.settings.max_health)


func test_storm_gets_worse_over_time() -> void:
	await _open()
	await _move(_player, _outside())
	_mission.time_left = 0.0
	await wait_physics_frames(2)
	var early: float = _mission.storm_damage_per_second()
	await wait_physics_frames(10)
	assert_gt(_mission.storm_damage_per_second(), early)


func test_storm_spares_players_aboard() -> void:
	var other: Player = PLAYER_SCENE.instantiate() as Player
	_map.add_child(other)
	await _move(other, _inside())
	await _open()
	await _move(_player, _outside())
	_mission.time_left = 0.0
	await wait_physics_frames(10)
	assert_eq(other.health, other.settings.max_health)
	assert_lt(_player.health, _player.settings.max_health)


func test_dying_in_storm_loses_mission_and_cargo() -> void:
	await _open()
	await _move(_player, _outside())
	_player.add_cargo(CYAN, 100.0)
	_mission.time_left = 0.0
	_mission.storm_time = 1000.0
	await wait_physics_frames(10)
	assert_true(_player.dead)
	assert_eq(_mission.state, Mission.State.LOST)
	assert_signal_emit_count(_mission, "lost", 1)
	assert_signal_not_emitted(_mission, "returned")
	assert_true(_player.cargo.is_empty())
	assert_false(_ship.hold.has(CYAN), "nothing reached the hold")


func test_respawn_aboard_after_lost_mission() -> void:
	await _open()
	await _move(_player, _outside())
	_player.take_damage(_player.settings.max_health)
	await wait_physics_frames(2)
	assert_eq(_mission.state, Mission.State.LOST)
	assert_false(_ship.ramp_button.enabled, "the dead are still lying outside")
	var delay_frames: int = ceili(_mission.settings.respawn_delay * Engine.physics_ticks_per_second)
	await wait_physics_frames(delay_frames + 2)
	assert_false(_player.dead)
	assert_true(_ship.is_aboard(_player))
	assert_eq(_player.health, _player.settings.max_health)
	assert_true(_ship.ramp_button.enabled)
	await _wait_for_ramp()
	assert_true(_ship.is_ramp_up())
	_ship.ramp_button.use(_player)
	await wait_physics_frames(2)
	assert_eq(_mission.state, Mission.State.OPEN, "the button starts the next run")


func test_dying_aboard_without_mission_respawns() -> void:
	assert_eq(_mission.state, Mission.State.CLOSED)
	_player.take_damage(_player.settings.max_health)
	await wait_physics_frames(2)
	assert_false(_ship.ramp_button.enabled, "nobody can start a run while someone is dead")
	var delay_frames: int = ceili(_mission.settings.respawn_delay * Engine.physics_ticks_per_second)
	await wait_physics_frames(delay_frames + 2)
	assert_false(_player.dead)
	assert_eq(_player.global_position, _ship.get_respawn_position())
	assert_true(_ship.ramp_button.enabled)
	assert_eq(_mission.state, Mission.State.CLOSED)


func test_tuning_duration_updates_timer() -> void:
	_mission.settings.duration = 120.0
	await wait_physics_frames(2)
	assert_eq(_mission.time_left, 120.0, "before the start: the new duration")
	await _open()
	await _move(_player, _outside())
	var time_left: float = _mission.time_left
	_mission.settings.duration = 100.0
	await wait_physics_frames(1)
	assert_almost_eq(_mission.time_left, time_left - 20.0, 0.1, "while running: by the difference")


func test_returning_stores_cargo_in_hold() -> void:
	await _open()
	await _move(_player, _outside())
	_player.add_cargo(CYAN, 150.0)
	await _move(_player, _inside())
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_true(_player.cargo.is_empty())
	assert_eq(_ship.hold[CYAN], 150.0)
	var rack: CargoRack = _ship.get_node("HoldRack")
	assert_eq(rack.canister_count(CYAN), 1)


func test_hold_keeps_cargo_over_runs() -> void:
	for run: int in 2:
		_ship.ramp_button.use(_player)
		await _wait_for_ramp()
		await _move(_player, _outside())
		_player.add_cargo(CYAN, 100.0)
		await _move(_player, _inside())
	assert_eq(_ship.hold[CYAN], 200.0)


func test_next_run_heals_players() -> void:
	await _open()
	await _move(_player, _outside())
	_player.take_damage(40.0)
	await _move(_player, _inside())
	assert_eq(_mission.state, Mission.State.RETURNED)
	_ship.ramp_button.use(_player)
	assert_eq(_player.health, _player.settings.max_health)


func test_mission_won_when_the_living_are_aboard() -> void:
	var other: Player = PLAYER_SCENE.instantiate() as Player
	_map.add_child(other)
	await _move(other, _inside())
	await _open()
	await _move(_player, _outside())
	await _move(other, _outside())
	other.add_cargo(CYAN, 50.0)
	other.take_damage(other.settings.max_health)
	_player.add_cargo(CYAN, 80.0)
	await wait_physics_frames(2)
	assert_eq(_mission.state, Mission.State.RUNNING, "one player is still alive outside")
	await _move(_player, _inside())
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_eq(_ship.hold[CYAN], 80.0, "the dead player's cargo is lost")
	assert_false(other.dead, "the dead respawn aboard")
	await wait_physics_frames(3)
	assert_true(_ship.is_aboard(other))


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
