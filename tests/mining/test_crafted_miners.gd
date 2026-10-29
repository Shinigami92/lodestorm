extends GutTest
## Placing a player's crafted and standard-issue miners, and picking them up again.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const PLATING: Upgrade = preload("res://game/progression/upgrades/miner_plating.tres")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")

var _map: Node3D
var _player: Player
var _nodes: Array[OreNode] = []


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_nodes.clear()
	for node: Node in get_tree().get_nodes_in_group(OreNode.GROUP):
		_nodes.append(node as OreNode)
	await wait_physics_frames(2)


func test_a_crafted_miner_wears_its_plate() -> void:
	var miner: Miner = _place(0)
	assert_eq(miner.crafted, _player.fleet.get_miner(1))
	assert_false(miner.standard)
	assert_eq(miner.owned_by, _player)
	var plate := miner.get_node("Model/Plate") as Node3D
	assert_true(plate.visible)
	assert_eq((plate.get_node("Number") as Label3D).text, "M-01")
	var strip := plate.get_node("Strip") as MeshInstance3D
	assert_eq((strip.material_override as StandardMaterial3D).albedo_color, _player.color())


func test_standard_issue_miners_fill_up_slower_and_unnumbered() -> void:
	var miner: Miner = _place(1, 0)
	assert_null(miner.crafted)
	assert_true(miner.standard)
	assert_almost_eq(
		miner.fill_rate(),
		miner.settings.fill_rate * miner.ore_type.mine_rate * miner.settings.standard_fill_share,
		1e-5
	)
	assert_eq((miner.get_node("Model/Plate/Number") as Label3D).text, "")


func test_a_crafted_miner_uses_its_own_levels() -> void:
	var crafted: CraftedMiner = _player.fleet.get_miner(1)
	crafted.upgrades.raise(PLATING)
	crafted.upgrades.raise(DRILL)
	var miner: Miner = _place(0)
	assert_eq(miner.max_health(), miner.settings.max_health * PLATING.levels[0].multiplier)
	assert_eq(miner.health, miner.max_health())
	assert_almost_eq(
		miner.fill_rate(),
		miner.settings.fill_rate * miner.ore_type.mine_rate * DRILL.levels[0].multiplier,
		1e-5
	)


func test_no_more_miners_than_open_cradles_per_run() -> void:
	assert_eq(_player.fleet.per_run(), Cradles.START)
	_player.fleet.standard_out = _player.fleet.standard_count()
	_player.fleet.get_miner(1).out = true
	_player.global_position = _nodes[0].global_position + Vector3(1.0, 0.0, 0.0)
	await wait_physics_frames(2)
	assert_null(_player.place_miner())
	assert_true(_nodes[0].is_free())


func test_interact_picks_a_miner_up_with_its_ore() -> void:
	var miner: Miner = _place(0)
	miner.amount = 40.0
	miner.take_damage(30.0)
	_player.global_position = miner.global_position + Vector3(2.0, 0.0, 0.0)
	_player.reset_physics_interpolation()
	await wait_physics_frames(3)
	assert_eq(_player.interact_target.get_parent(), miner, "its pickup")
	_player.interact()
	assert_false(miner.is_queued_for_deletion(), "it takes time")
	_player.handling.update(miner.settings.pick_up_time)
	assert_true(miner.is_queued_for_deletion())
	assert_true(_nodes[0].is_free())
	assert_almost_eq(_player.cargo.amount(miner.ore_type), 40.0, 1.0)
	var crafted: CraftedMiner = _player.fleet.get_miner(1)
	assert_false(crafted.out)
	assert_eq(_player.fleet.left_to_place(), _player.fleet.per_run())
	await wait_physics_frames(1)
	var again: Miner = _place(1)
	assert_eq(again.crafted, crafted, "placed again")
	assert_lt(again.health, again.max_health(), "its damage came along")


func test_a_teammates_pickup_goes_back_to_the_owner() -> void:
	var miner: Miner = _place(0)
	var other := preload("res://game/player/player.tscn").instantiate() as Player
	_map.add_child(other)
	await wait_physics_frames(1)
	assert_true(miner.pick_up(other))
	assert_false(_player.fleet.get_miner(1).out)
	assert_eq(other.fleet.left_to_place(), other.fleet.per_run(), "not the teammate's")


func test_a_miner_left_behind_cannot_be_picked_up() -> void:
	var miner: Miner = _place(0)
	_player.fleet.end_run("there")
	assert_false(miner.pick_up(_player))
	assert_true(_player.fleet.is_empty(1))


func test_loose_miners_have_no_plate_or_pickup() -> void:
	var miner: Miner = _nodes[0].place_miner(_player.miner_scene)
	assert_false((miner.get_node("Model/Plate") as Node3D).visible)
	assert_null(miner.get_node_or_null("Pickup"))
	assert_false(miner.pick_up(_player))


## Places the crafted miner in cradle `number` (0: a standard-issue one) on node `index`.
func _place(index: int, number: int = 1) -> Miner:
	var choice := MinerChoice.new(_player.fleet.get_miner(number) if number > 0 else null)
	return _nodes[index].place_miner(_player.miner_scene, _player.fleet, _player, false, choice)
