extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")

var _map: Node3D
var _player: Player
var _node: OreNode


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_node = _map.get_node("Location/OreNodes/CyanA") as OreNode


func test_connects_in_range_and_transfers() -> void:
	var miner: Miner = _place_miner(0.0, 10.0)
	miner.amount = 10.0
	_move_player(_node.global_position + Vector3(3.0, 0.0, 0.0))
	await wait_physics_frames(roundi(Engine.physics_ticks_per_second * 0.25))
	assert_eq(miner.hose_target, _player)
	assert_almost_eq(_carried(_node.ore_type), 5.0, 0.5)
	assert_almost_eq(miner.amount + _carried(_node.ore_type), 10.0, 0.001)


func test_transfer_stops_when_miner_is_empty() -> void:
	var miner: Miner = _place_miner(0.0, 10.0)
	miner.amount = 2.0
	_move_player(_node.global_position + Vector3(3.0, 0.0, 0.0))
	await wait_physics_frames(roundi(Engine.physics_ticks_per_second * 0.5))
	assert_eq(miner.amount, 0.0)
	assert_almost_eq(_carried(_node.ore_type), 2.0, 0.001)


func test_no_connection_out_of_range() -> void:
	var miner: Miner = _place_miner(0.0, 10.0)
	miner.amount = 10.0
	_move_player(_node.global_position + Vector3(6.0, 0.0, 0.0))
	await wait_physics_frames(5)
	assert_null(miner.hose_target)
	assert_eq(miner.amount, 10.0)
	assert_eq(_carried(_node.ore_type), 0.0)


func test_disconnects_when_leaving_and_reconnects() -> void:
	var miner: Miner = _place_miner(0.0, 100.0)
	miner.amount = 100.0
	_move_player(_node.global_position + Vector3(3.0, 0.0, 0.0))
	await wait_physics_frames(2)
	assert_eq(miner.hose_target, _player)
	_move_player(_node.global_position + Vector3(6.0, 0.0, 0.0))
	await wait_physics_frames(2)
	assert_null(miner.hose_target)
	var carried: float = _carried(_node.ore_type)
	await wait_physics_frames(5)
	assert_eq(_carried(_node.ore_type), carried)
	_move_player(_node.global_position + Vector3(0.0, 0.0, 3.0))
	await wait_physics_frames(2)
	assert_eq(miner.hose_target, _player)
	assert_gt(_carried(_node.ore_type), carried)


func test_hose_is_visible_only_while_connected() -> void:
	var miner: Miner = _place_miner(0.0, 10.0)
	var hose: Hose = miner.get_node("Hose")
	_move_player(_node.global_position + Vector3(6.0, 0.0, 0.0))
	await wait_physics_frames(2)
	await wait_process_frames(2)
	assert_false(hose.visible)
	_move_player(_node.global_position + Vector3(3.0, 0.0, 0.0))
	await wait_physics_frames(2)
	await wait_process_frames(2)
	assert_true(hose.visible)
	assert_gt(hose.get_aabb().size.length(), 2.0)


func test_several_miners_connect_at_once() -> void:
	var other_node: OreNode = _map.get_node("Location/OreNodes/GreenA") as OreNode
	var miner: Miner = _place_miner(0.0, 10.0)
	var other: Miner = other_node.place_miner(_player.miner_scene)
	other.settings = miner.settings
	miner.settings.hose_range = 6.0
	miner.amount = 1.0
	other.amount = 1.0
	# Between both nodes, about 5.3 m from each.
	_move_player((_node.global_position + other_node.global_position) * 0.5)
	await wait_physics_frames(roundi(Engine.physics_ticks_per_second * 0.5))
	assert_eq(_carried(_node.ore_type), 1.0)
	assert_eq(_carried(other_node.ore_type), 1.0)


func test_long_hose_rests_on_ground() -> void:
	var hose := Hose.new()
	add_child_autofree(hose)
	hose.build(Vector3(0.0, 1.0, 0.0), Vector3(10.0, 1.0, 0.0), 0.0)
	assert_between(hose.get_aabb().position.y, -0.001, 0.02)


func _carried(ore_type: OreType) -> float:
	return _player.cargo.get(ore_type, 0.0)


func _move_player(target: Vector3) -> void:
	_player.global_position = target
	_player.reset_physics_interpolation()


## Places a miner on `_node` with its own settings, so tests don't depend on tuning values.
func _place_miner(fill_rate: float, capacity: float) -> Miner:
	var miner: Miner = _node.place_miner(_player.miner_scene)
	miner.settings = MinerSettings.new()
	miner.settings.fill_rate = fill_rate
	miner.settings.capacity = capacity
	miner.settings.hose_range = 5.0
	miner.settings.transfer_rate = 20.0
	return miner
