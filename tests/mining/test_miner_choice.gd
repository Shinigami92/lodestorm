extends GutTest
## Choosing which miner to place: by default the softest drill that still mines the ore at full
## speed (else the fastest), `miner_prev`/`miner_next` stepping through the miners still to place,
## the choice sticking until it's placed, and a preview of it on the node it would go on.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const TANK: Upgrade = preload("res://game/progression/upgrades/miner_tank.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")

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


func after_each() -> void:
	Input.action_release(&"miner_next")


func test_options_are_the_crafted_ones_by_number_then_standard_issue() -> void:
	var fleet: MinerFleet = _six_cradles()
	assert_eq(_numbers(MinerChoice.options(fleet)), [1, 2, 3, 4, 5, 0] as Array[int])
	fleet.take(fleet.get_miner(2))
	assert_eq(_numbers(MinerChoice.options(fleet)), [1, 3, 4, 5, 0] as Array[int])
	fleet.take(null)
	assert_eq(_numbers(MinerChoice.options(fleet)), [1, 3, 4, 5] as Array[int])


func test_default_is_the_softest_drill_at_full_speed() -> void:
	var fleet: MinerFleet = _six_cradles()
	_raise(fleet.get_miner(1), DRILL, 4)
	_raise(fleet.get_miner(2), DRILL, 1)
	_raise(fleet.get_miner(3), DRILL, 2)
	assert_eq(
		_number(MinerChoice.default_for(fleet, MERIDINE)), 3, "MK3: the softest at full speed"
	)
	assert_eq(_number(MinerChoice.default_for(fleet, KYRITE)), 0, "standard-issue on a tie")
	while fleet.standard_left() > 0:
		fleet.take(null)
	assert_eq(_number(MinerChoice.default_for(fleet, KYRITE)), 4, "then the first MK1 by number")


func test_default_without_full_speed_is_the_fastest() -> void:
	var fleet: MinerFleet = _six_cradles()
	_raise(fleet.get_miner(5), DRILL, 1)
	assert_eq(_number(MinerChoice.default_for(fleet, MERIDINE)), 5, "MK2: still too soft")
	while fleet.left_to_place() > 0:
		fleet.take(MinerChoice.default_for(fleet, MERIDINE).crafted)
	assert_null(MinerChoice.default_for(fleet, MERIDINE), "none left")


func test_fill_time_counts_the_tank_and_what_the_node_holds() -> void:
	var node: OreNode = _nodes[0]
	node.ore_type = KYRITE
	var standard := MinerChoice.new()
	var settings: MinerSettings = MinerChoice.SETTINGS
	var rate: float = settings.fill_rate * settings.standard_fill_share * KYRITE.mine_rate
	assert_almost_eq(standard.fill_time(node), settings.capacity / rate, 0.01)
	node.mine(node.amount - 10.0)
	assert_almost_eq(standard.fill_time(node), 10.0 / rate, 0.01, "until it runs dry")


func test_stepping_goes_through_the_miners_and_wraps() -> void:
	_player.fleet.cradles.restore(3)
	_player.fleet.build_all()
	_player.fleet.cradles.restore(4)
	var node: OreNode = _target(KYRITE)
	assert_eq(_number(_player.picker.choice_for(node)), 0, "the default: standard-issue")
	assert_true(_player.picker.step(1))
	assert_eq(_number(_player.picker.choice_for(node)), 1, "wrapped to the first")
	_player.picker.step(1)
	assert_eq(_number(_player.picker.choice_for(node)), 2)
	_player.picker.step(-1)
	_player.picker.step(-1)
	assert_eq(_number(_player.picker.choice_for(node)), 0)


func test_no_stepping_without_a_node() -> void:
	assert_null(_player.miner_target)
	assert_false(_player.picker.step(1))


func test_choice_sticks_until_placed() -> void:
	var node: OreNode = _target(KYRITE)
	assert_eq(_number(_player.picker.choice_for(node)), 0)
	Input.action_press(&"miner_next")
	await wait_physics_frames(1)
	assert_eq(_number(_player.picker.choice_for(node)), 1, "M-01")
	var other: OreNode = _nodes[1]
	other.ore_type = KYRITE
	assert_eq(_number(_player.picker.choice_for(other)), 1, "also on another node")
	var miner: Miner = _player.place_miner()
	assert_eq(miner.crafted.number, 1)
	assert_null(_player.picker.chosen, "the next starts on the default")


func test_preview_shows_the_miner_to_place() -> void:
	var node: OreNode = _target(MERIDINE)
	await wait_physics_frames(1)
	await wait_process_frames(2)
	var preview: MinerPreview = _player.picker.preview
	assert_true(preview.visible)
	assert_eq(preview.node, node)
	assert_almost_eq(preview.global_position, node.get_mount_position(), Vector3.ONE * 0.01)
	assert_eq(_number(preview.choice), 1, "the fastest: no drill mines it at full speed")
	assert_eq(preview.tint, MinerPreview.TOO_SOFT_COLOR)
	var plate := preview.find_child("Number", true, false) as Label3D
	assert_eq(plate.text, "M-01")
	var parts := preview.find_child("Parts", true, false) as Label3D
	assert_eq(parts.text, "Drill MK1 · Tank MK1")


func test_preview_of_a_drill_at_full_speed() -> void:
	_raise(_player.fleet.get_miner(1), DRILL, 2)
	_raise(_player.fleet.get_miner(1), TANK, 2)
	_target(MERIDINE)
	await wait_physics_frames(1)
	var preview: MinerPreview = _player.picker.preview
	assert_eq(_number(preview.choice), 1)
	assert_eq(preview.tint, MinerPreview.FULL_SPEED_COLOR)
	var parts := preview.find_child("Parts", true, false) as Label3D
	assert_eq(parts.text, "Drill MK3 · Tank MK3")


func test_preview_goes_once_placed_and_when_none_is_left() -> void:
	_target(KYRITE)
	await wait_physics_frames(1)
	var preview: MinerPreview = _player.picker.preview
	assert_true(preview.wanted)
	_player.place_miner()
	assert_false(preview.visible, "the building hologram takes over")
	await wait_physics_frames(1)
	assert_false(preview.wanted, "while it's placed nearby")
	_player.handling.cancel()
	while _player.fleet.left_to_place() > 0:
		_player.fleet.take(MinerChoice.default_for(_player.fleet, KYRITE).crafted)
	await wait_physics_frames(1)
	assert_false(preview.wanted, "none left")


## A fleet with every cradle open and a miner built in each but the last (a standard-issue one
## fills up).
func _six_cradles() -> MinerFleet:
	var fleet := MinerFleet.new()
	fleet.cradles.restore(MinerFleet.SLOTS - 1)
	fleet.build_all()
	fleet.cradles.restore(MinerFleet.SLOTS)
	return fleet


## Gives the first ore node `ore_type` and moves the player next to it, its target.
func _target(ore_type: OreType) -> OreNode:
	var node: OreNode = _nodes[0]
	node.ore_type = ore_type
	_player.global_position = node.global_position + Vector3(1.5, 0.0, 0.0)
	_player.reset_physics_interpolation()
	_player.miner_target = node
	return node


func _raise(miner: CraftedMiner, upgrade: Upgrade, times: int) -> void:
	for i: int in times:
		miner.upgrades.raise(upgrade)


## The crafted miner's number, 0 for a standard-issue one, -1 for none.
func _number(choice: MinerChoice) -> int:
	if not choice:
		return -1
	return choice.crafted.number if choice.crafted else 0


func _numbers(choices: Array[MinerChoice]) -> Array[int]:
	var result: Array[int] = []
	for choice: MinerChoice in choices:
		result.append(_number(choice))
	return result
