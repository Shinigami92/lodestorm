extends GutTest

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")

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
	_mission.settings = _mission.settings.duplicate()
	_mission.settings.respawn_delay = 0.25
	await wait_physics_frames(2)
	TEST_MAP.pick_mission(_map)
	watch_signals(_mission)
	watch_signals(GameEvents.bus)


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
	var brief: MissionBrief = _voyage.brief
	await _open()
	await _move(_player, _outside())
	_player.add_cargo(KYRITE, 100.0)
	_mission.time_left = 0.0
	_mission.storm_time = 1000.0
	await wait_physics_frames(10)
	assert_true(_player.dead)
	assert_eq(_mission.state, Mission.State.LOST)
	assert_signal_emit_count(_mission, "lost", 1)
	assert_signal_not_emitted(_mission, "returned")
	assert_signal_emitted_with_parameters(GameEvents.bus, "mission_ended", [brief, false])
	assert_null(_voyage.brief, "new missions on offer")
	assert_true(_player.cargo.is_empty())
	assert_false(_player.hold.items.has(KYRITE), "nothing reached the hold")


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
	assert_false(_ship.ramp_button.enabled, "the lost mission is done: pick the next one")
	await _wait_for_ramp()
	assert_true(_ship.is_ramp_up())
	TEST_MAP.pick_mission(_map)
	await wait_physics_frames(1)
	assert_true(_ship.ramp_button.enabled)
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
	var length: float = _voyage.brief.length
	_mission.settings.duration = 120.0
	await wait_physics_frames(2)
	assert_eq(_mission.time_left, 120.0 * length, "before the start: the new duration")
	await _open()
	await _move(_player, _outside())
	var time_left: float = _mission.time_left
	_mission.settings.duration = 100.0
	await wait_physics_frames(1)
	assert_almost_eq(
		_mission.time_left, time_left - 20.0 * length, 0.1, "while running: by the difference"
	)


func test_returning_stores_cargo_in_hold() -> void:
	await _open()
	await _move(_player, _outside())
	_player.add_cargo(KYRITE, 150.0)
	await _move(_player, _inside())
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_true(_player.cargo.is_empty())
	assert_eq(_player.hold.amount(KYRITE), 150.0)
	var hold: OreHold = _ship.get_node("OreHold")
	assert_gt(hold.get_tank(KYRITE).fill_level(), 0.0, "its tank shows it")


func test_banking_during_a_run_stores_cargo_and_the_run_goes_on() -> void:
	await _open()
	await _move(_player, _outside())
	_player.add_cargo(KYRITE, 60.0)
	_mission.bank([_player])
	assert_true(_player.cargo.is_empty())
	assert_eq(_player.hold.amount(KYRITE), 60.0)
	assert_eq(_mission.state, Mission.State.RUNNING, "still outside, still running")
	assert_signal_emitted(GameEvents.bus, "ore_hauled")
	_player.add_cargo(KYRITE, 40.0)
	await _move(_player, _inside())
	assert_eq(_player.hold.amount(KYRITE), 100.0, "the rest comes aboard at the end")


func test_hold_keeps_cargo_over_runs() -> void:
	for run: int in 2:
		TEST_MAP.pick_mission(_map)
		await _open()
		await _move(_player, _outside())
		_player.add_cargo(KYRITE, 100.0)
		await _move(_player, _inside())
	assert_eq(_player.hold.amount(KYRITE), 200.0)


## While the heat shield's next plate is the ship's project, the haul pays into it first.
func test_returning_pays_the_ships_project_first() -> void:
	_ship.heat_shield.set_project()
	await _open()
	await _move(_player, _outside())
	_player.add_cargo(MERIDINE, 120.0)
	_player.add_cargo(KYRITE, 30.0)
	await _move(_player, _inside())
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_eq(_ship.heat_shield.paid[MERIDINE], 120.0)
	var stored: float = _player.hold.amount(MERIDINE)
	assert_eq(stored, 0.0, "the plate took all of it")
	assert_eq(_player.hold.amount(KYRITE), 30.0)


func test_health_carries_over_to_the_next_run() -> void:
	await _open()
	await _move(_player, _outside())
	_player.take_damage(40.0)
	await _move(_player, _inside())
	assert_eq(_mission.state, Mission.State.RETURNED)
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	assert_eq(_player.health, _player.settings.max_health - 40.0, "the med beds heal")


func test_mission_won_when_the_living_are_aboard() -> void:
	var brief: MissionBrief = _voyage.brief
	var other: Player = PLAYER_SCENE.instantiate() as Player
	_map.add_child(other)
	await _move(other, _inside())
	await _open()
	await _move(_player, _outside())
	await _move(other, _outside())
	other.add_cargo(KYRITE, 50.0)
	other.take_damage(other.settings.max_health)
	_player.add_cargo(KYRITE, 80.0)
	await wait_physics_frames(2)
	assert_eq(_mission.state, Mission.State.RUNNING, "one player is still alive outside")
	await _move(_player, _inside())
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_signal_emitted_with_parameters(GameEvents.bus, "mission_ended", [brief, true])
	assert_eq(_player.hold.amount(KYRITE), 80.0, "the dead player's cargo is lost")
	assert_false(other.dead, "the dead respawn aboard")
	await wait_physics_frames(3)
	assert_true(_ship.is_aboard(other))


func test_crafted_miners_left_on_the_planet_are_lost() -> void:
	_player.fleet.build_all()
	await _open()
	await _move(_player, _outside())
	var nodes: Array[Node] = get_tree().get_nodes_in_group(OreNode.GROUP)
	var left := (nodes[0] as OreNode).place_miner(_player.miner_scene, _player.fleet, _player)
	var taken := (nodes[1] as OreNode).place_miner(_player.miner_scene, _player.fleet, _player)
	var left_number: int = left.crafted.number
	var taken_number: int = taken.crafted.number
	assert_true(taken.pick_up(_player))
	var where: String = _voyage.brief.place_name(_voyage.settings.system)
	await _move(_player, _inside())
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_true(_player.fleet.is_empty(left_number), "left behind")
	assert_eq(_player.fleet.lost_at[left_number], where)
	assert_not_null(_player.fleet.get_miner(taken_number), "picked up in time")


func test_crafted_miners_are_lost_when_everyone_dies() -> void:
	await _open()
	await _move(_player, _outside())
	var node := get_tree().get_nodes_in_group(OreNode.GROUP)[0] as OreNode
	node.place_miner(_player.miner_scene, _player.fleet, _player)
	_player.take_damage(_player.settings.max_health)
	await wait_physics_frames(2)
	assert_eq(_mission.state, Mission.State.LOST)
	assert_true(_player.fleet.is_empty(1))


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
