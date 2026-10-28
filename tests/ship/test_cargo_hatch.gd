extends GutTest

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")

var _map: Node3D
var _player: Player
var _mission: Mission
var _ship: Ship
var _hatch: CargoHatch


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_mission = _map.get_node("Mission") as Mission
	_ship = _map.get_node("Ship") as Ship
	_hatch = _ship.get_node("CargoHatch") as CargoHatch
	_ship.ramp_duration = 0.25
	await wait_physics_frames(2)
	TEST_MAP.pick_mission(_map)
	watch_signals(GameEvents.bus)


func test_stowed_and_shut_until_the_ramp_is_down_for_a_run() -> void:
	var slide: Node3D = _hatch.get_node("Slide")
	assert_false(_hatch.enabled)
	assert_gt(slide.position.y, 1.0, "up on the tail with the ramp")
	await _open()
	assert_true(_hatch.enabled)
	assert_eq(slide.position.y, 0.0, "down on the ground with the ramp")


func test_banks_everything_carried_and_the_run_goes_on() -> void:
	await _open()
	await _move(_player, _beside_hatch())
	_player.add_cargo(KYRITE, 60.0)
	_player.add_cargo(MERIDINE, 20.0)
	assert_eq(_player.interact(), _hatch as Interactable, "the hatch is what the player uses")
	assert_true(_hatch.is_flowing(_player))
	await _wait(CargoHatch.FLOW_TIME * 0.5)
	assert_gt(_carried(_player), 0.0, "it flows in over a while")
	await _wait(CargoHatch.FLOW_TIME * 0.5 + 0.2)
	assert_false(_hatch.is_flowing(_player))
	assert_almost_eq(_carried(_player), 0.0, 0.001)
	assert_almost_eq(_player.hold.amount(KYRITE), 60.0, 0.001)
	assert_almost_eq(_player.hold.amount(MERIDINE), 20.0, 0.001)
	assert_signal_emit_count(GameEvents.bus, "ore_hauled", 2, "once per ore, not every tick")
	assert_eq(_mission.state, Mission.State.RUNNING, "still outside, still running")


func test_walking_off_stops_the_flow_and_banks_what_went_in() -> void:
	await _open()
	await _move(_player, _beside_hatch())
	_player.add_cargo(KYRITE, 100.0)
	_player.interact()
	await _wait(CargoHatch.FLOW_TIME * 0.5)
	await _move(_player, _ship.to_global(Vector3(24.0, 0.0, 7.0)))
	assert_false(_hatch.is_flowing(_player))
	var banked: float = _player.hold.amount(KYRITE)
	assert_between(banked, 20.0, 80.0, "about half went in")
	assert_almost_eq(_carried(_player) + banked, 100.0, 0.001, "the rest stays carried")


func test_players_bank_at_the_same_time() -> void:
	var other: Player = PLAYER_SCENE.instantiate() as Player
	_map.add_child(other)
	await _open()
	await _move(_player, _beside_hatch())
	await _move(other, _beside_hatch() + Vector3(0.0, 0.0, 0.8))
	_player.add_cargo(KYRITE, 30.0)
	other.add_cargo(MERIDINE, 10.0)
	_hatch.use(_player)
	_hatch.use(other)
	assert_true(_hatch.is_flowing(_player) and _hatch.is_flowing(other))
	await _wait(CargoHatch.FLOW_TIME + 0.2)
	assert_almost_eq(_player.hold.amount(KYRITE), 30.0, 0.001)
	assert_almost_eq(_player.hold.amount(MERIDINE), 10.0, 0.001, "everyone gets the whole haul")
	assert_almost_eq(other.hold.amount(KYRITE), 30.0, 0.001)


func test_nothing_carried_starts_no_flow() -> void:
	await _open()
	await _move(_player, _beside_hatch())
	_hatch.use(_player)
	assert_false(_hatch.is_flowing(_player))


func test_dying_mid_flow_keeps_what_went_in() -> void:
	await _open()
	await _move(_player, _beside_hatch())
	_player.add_cargo(KYRITE, 100.0)
	_player.interact()
	await _wait(CargoHatch.FLOW_TIME * 0.5)
	_player.take_damage(INF)
	await wait_physics_frames(2)
	assert_false(_hatch.is_flowing(_player))
	assert_between(_player.hold.amount(KYRITE), 20.0, 80.0, "what went in is banked")
	assert_true(_player.cargo.is_empty(), "the rest was dropped")


func _open() -> void:
	_ship.ramp_button.use(_player)
	await _wait(_ship.ramp_duration)


func _wait(seconds: float) -> void:
	await wait_physics_frames(ceili(seconds * Engine.physics_ticks_per_second) + 2)


## On the ground by the hatch, on the ramp's side away from the ship.
func _beside_hatch() -> Vector3:
	return _ship.to_global(Vector3(16.8, 0.0, 7.0))


func _move(player: Player, target: Vector3) -> void:
	player.global_position = target
	player.reset_physics_interpolation()
	await wait_physics_frames(5)


func _carried(player: Player) -> float:
	var total: float = 0.0
	for ore_type: OreType in player.cargo:
		total += player.cargo[ore_type]
	return total
