extends GutTest

const TEST_MAP := preload("res://tests/support/map_fixture.gd")

var _map: Node3D
var _player: Player
var _node: OreNode
var _miner: Miner


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_node = _map.get_node("Location/OreNodes/KyriteA") as OreNode
	_miner = _node.place_miner(_player.miner_scene)
	_miner.settings = _miner.settings.duplicate() as MinerSettings
	_miner.settings.fill_rate = 10.0
	watch_signals(_miner)


func test_starts_undamaged() -> void:
	assert_eq(_miner.health, _miner.settings.max_health)
	assert_false(_miner.broken)


func test_breaks_down_at_zero_health_and_stops_mining() -> void:
	_miner.take_damage(_miner.settings.max_health * 0.5)
	assert_false(_miner.broken)
	_miner.take_damage(_miner.settings.max_health)
	assert_eq(_miner.health, 0.0)
	assert_true(_miner.broken)
	assert_signal_emit_count(_miner, "broke", 1)
	var amount: float = _miner.amount
	await wait_physics_frames(10)
	assert_eq(_miner.amount, amount, "no mining while broken")


func test_broken_miner_keeps_its_ore_from_the_hose() -> void:
	await _wait_physics(0.3)
	_miner.take_damage(_miner.settings.max_health)
	var amount: float = _miner.amount
	assert_gt(amount, 0.0)
	_miner.settings.repair_rate = 0.0
	_move_player(3.0)
	await wait_physics_frames(10)
	assert_null(_miner.hose_target)
	assert_eq(_miner.amount, amount)
	var carried: float = _player.cargo.amount(_node.ore_type)
	assert_eq(carried, 0.0)


func test_player_next_to_it_repairs_it_and_it_works_again() -> void:
	_miner.take_damage(_miner.settings.max_health)
	_miner.settings.repair_rate = _miner.settings.max_health * 2.0
	_move_player(_miner.settings.repair_range - 0.5)
	await _wait_physics(0.25)
	assert_true(_miner.broken, "only once repaired completely")
	assert_gt(_miner.health, 0.0)
	await _wait_physics(0.4)
	assert_false(_miner.broken)
	assert_eq(_miner.health, _miner.settings.max_health)
	assert_signal_emit_count(_miner, "repaired", 1)
	assert_eq(_miner.hose_target, _player, "hose connects again")


func test_no_repair_out_of_range() -> void:
	_miner.take_damage(_miner.settings.max_health)
	_move_player(_miner.settings.repair_range + 0.5)
	await wait_physics_frames(10)
	assert_eq(_miner.health, 0.0)


func test_repairs_damage_on_a_working_miner() -> void:
	_miner.take_damage(_miner.settings.max_health * 0.5)
	_move_player(_miner.settings.repair_range - 0.5)
	await _wait_physics(0.3)
	assert_gt(_miner.health, _miner.settings.max_health * 0.5)


func test_any_working() -> void:
	assert_true(Miner.any_working(get_tree()))
	_miner.take_damage(_miner.settings.max_health)
	assert_false(Miner.any_working(get_tree()))


func _move_player(distance: float) -> void:
	_player.global_position = _node.global_position + Vector3(distance, 0.0, 0.0)
	_player.reset_physics_interpolation()


## Waits `seconds` of physics time: on a busy machine it falls behind the wall clock that
## `wait_seconds` counts.
func _wait_physics(seconds: float) -> void:
	await wait_physics_frames(roundi(seconds * Engine.physics_ticks_per_second))
