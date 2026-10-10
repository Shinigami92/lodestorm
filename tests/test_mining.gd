extends GutTest

const TEST_MAP: PackedScene = preload("res://scenes/maps/test_map.tscn")

var _map: Node3D
var _player: Player
var _node: OreNode


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_node = _map.get_node("OreNodes/CyanA") as OreNode


func after_each() -> void:
	Input.action_release(&"place_miner")


func test_map_has_several_ore_types() -> void:
	var types: Array[OreType] = []
	for node: OreNode in get_tree().get_nodes_in_group(OreNode.GROUP):
		assert_not_null(node.ore_type, "%s has no ore type" % node.name)
		if node.ore_type not in types:
			types.append(node.ore_type)
	assert_between(types.size(), 2, 3)


func test_nothing_to_place_on_out_of_range() -> void:
	assert_null(_player.place_miner())
	assert_null(_player.miner_target)


func test_places_miner_on_nearest_node_in_range() -> void:
	_move_player_next_to(_node)
	var miner: Miner = _player.place_miner()
	assert_not_null(miner)
	assert_eq(_node.miner, miner)
	assert_eq(miner.ore_type, _node.ore_type)
	assert_almost_eq(miner.global_position, _node.global_position, Vector3.ONE * 0.1)


func test_place_miner_action_places_miner() -> void:
	_move_player_next_to(_node)
	Input.action_press(&"place_miner")
	await wait_physics_frames(1)
	assert_not_null(_node.miner)


func test_only_one_miner_per_node() -> void:
	_move_player_next_to(_node)
	assert_not_null(_player.place_miner())
	assert_null(_player.place_miner())
	assert_eq(_node.get_node("MinerMount").get_child_count(), 1)


func test_target_node_is_highlighted_until_occupied() -> void:
	_move_player_next_to(_node)
	await wait_physics_frames(1)
	assert_eq(_player.miner_target, _node)
	assert_true(_node.highlighted)
	_player.place_miner()
	assert_null(_player.miner_target)
	assert_false(_node.highlighted)


func test_miner_fills_at_fill_rate() -> void:
	var miner: Miner = _place_miner(1.0, 100.0)
	await wait_physics_frames(Engine.physics_ticks_per_second)
	assert_almost_eq(miner.amount, 1.0, 0.05)


func test_miner_stops_when_full() -> void:
	var miner: Miner = _place_miner(60.0, 10.0)
	watch_signals(miner)
	await wait_physics_frames(Engine.physics_ticks_per_second)
	assert_eq(miner.amount, 10.0)
	assert_true(miner.is_full())
	assert_signal_emit_count(miner, "filled", 1)


func test_take_empties_miner_and_it_mines_again() -> void:
	var miner: Miner = _place_miner(60.0, 10.0)
	await wait_physics_frames(Engine.physics_ticks_per_second)
	assert_eq(miner.take(4.0), 4.0)
	assert_eq(miner.amount, 6.0)
	assert_eq(miner.take(100.0), 6.0)
	assert_eq(miner.amount, 0.0)
	assert_false(miner.is_full())
	await wait_physics_frames(5)
	assert_gt(miner.amount, 0.0)


func test_full_lamp_lights_up_when_full() -> void:
	var miner: Miner = _place_miner(60.0, 10.0)
	var lamp: Node3D = miner.get_node("FullLamp")
	assert_false(lamp.visible)
	await wait_physics_frames(Engine.physics_ticks_per_second)
	assert_true(lamp.visible)


func _move_player_next_to(node: OreNode) -> void:
	_player.global_position = node.global_position + Vector3(1.5, 0.0, 0.0)
	_player.reset_physics_interpolation()


## Places a miner on `_node` with its own settings, so tests don't depend on tuning values.
## Its hose never connects, so only mining changes the amount.
func _place_miner(fill_rate: float, capacity: float) -> Miner:
	var miner: Miner = _node.place_miner(_player.miner_scene)
	miner.settings = MinerSettings.new()
	miner.settings.fill_rate = fill_rate
	miner.settings.capacity = capacity
	miner.settings.hose_range = 0.0
	return miner
