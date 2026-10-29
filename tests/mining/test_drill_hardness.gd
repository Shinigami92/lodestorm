extends GutTest
## Harder ores need better drills: a drill too soft mines them slower, placing takes the softest
## drill that mines a node's ore at full speed, and the drill's and the silo's cards say which level
## mines what.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const CARD_SCENE: PackedScene = preload("res://game/stations/upgrade/upgrade_card.tscn")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const TANK: Upgrade = preload("res://game/progression/upgrades/miner_tank.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
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


func test_harder_ores_need_better_drills() -> void:
	var by_band: Dictionary[OreType.Band, int] = {OreType.Band.COMMON: 0, OreType.Band.MID: 1}
	for ore_type: OreType in OreCatalog.all().ores:
		if ore_type.band in by_band:
			assert_eq(ore_type.hardness, by_band[ore_type.band], ore_type.display_name)
		else:
			assert_between(ore_type.hardness, 2, 4, ore_type.display_name)
	assert_eq(MERIDINE.hardness, 2)
	var hardness: Array[int] = []
	for mk: int in range(1, DRILL.max_mk() + 1):
		hardness.append(DRILL.hardness_at(mk))
	assert_eq(hardness, [1, 1, 2, 2, 3, 3, 4, 4] as Array[int])
	assert_eq(DRILL.mk_for_hardness(0), 1)
	assert_eq(DRILL.mk_for_hardness(2), 3)
	assert_eq(DRILL.mk_for_hardness(4), 7)
	assert_eq(DRILL.mk_for_hardness(5), 0, "none")
	assert_eq(TANK.hardness, -1, "not a drill")


func test_drill_card_shows_the_ores_it_mines_at_full_speed() -> void:
	var card := CARD_SCENE.instantiate() as UpgradeCard
	add_child_autofree(card)
	var found: Dictionary[ItemType, bool] = {KYRITE: true, VYREL: true, MERIDINE: true}
	card.show_upgrade(DRILL, 2)
	card.show_reach(DRILL, 2, found)
	assert_eq(_badges(card, "%ReachOres"), ["Vyrel"])
	assert_string_contains((card.get_node("%ReachNextLabel") as Label).text, "MK3")
	assert_eq(_badges(card, "%ReachNextOres"), ["Meridine"])
	card.show_upgrade(DRILL, 3)
	card.show_reach(DRILL, 3, found)
	assert_eq(_badges(card, "%ReachOres"), ["Meridine"])
	assert_false((card.get_node("%ReachNext") as Control).visible, "MK4 adds no ore")
	card.show_upgrade(DRILL, 4)
	card.show_reach(DRILL, 4, found)
	assert_eq(
		(card.get_node("%ReachNextLabel") as Label).text,
		"MK5 mines harder ores too.",
		"none of them found yet"
	)
	card.show_upgrade(TANK, 1)
	card.show_reach(TANK, 1, found)
	assert_false((card.get_node("%Reach") as Control).visible, "only drills")


func test_a_drill_too_soft_mines_at_a_quarter_of_the_speed() -> void:
	_nodes[0].ore_type = MERIDINE
	var miner: Miner = _place(0)
	var settings: MinerSettings = miner.settings
	assert_true(miner.is_drill_too_soft(), "MK1 mines up to hardness 1")
	assert_almost_eq(
		miner.fill_rate(), settings.fill_rate * MERIDINE.mine_rate * settings.soft_drill_share, 1e-5
	)
	miner.upgrades.raise(DRILL)
	miner.upgrades.raise(DRILL)
	assert_false(miner.is_drill_too_soft(), "MK3 mines up to hardness 2")
	assert_almost_eq(
		miner.fill_rate(), settings.fill_rate * MERIDINE.mine_rate * DRILL.multiplier(3), 1e-5
	)


func test_standard_issue_drills_mine_mid_ores_at_full_speed() -> void:
	_player.fleet.get_miner(1).going_along = false
	_nodes[0].ore_type = VYREL
	_nodes[1].ore_type = MERIDINE
	var mid: Miner = _place(0)
	assert_true(mid.standard)
	assert_false(mid.is_drill_too_soft())
	var signature: Miner = _place(1)
	assert_true(signature.is_drill_too_soft())
	var settings: MinerSettings = signature.settings
	assert_almost_eq(
		signature.fill_rate(),
		(
			settings.fill_rate
			* MERIDINE.mine_rate
			* settings.standard_fill_share
			* settings.soft_drill_share
		),
		1e-5
	)


func test_placing_takes_the_softest_drill_at_full_speed() -> void:
	_player.fleet.cradles.restore(MinerFleet.SLOTS)
	_player.fleet.build_all()
	_player.fleet.get_miner(3).upgrades.raise(DRILL)
	_player.fleet.get_miner(3).upgrades.raise(DRILL)
	_player.fleet.get_miner(5).upgrades.raise(DRILL)
	_nodes[0].ore_type = MERIDINE
	_nodes[1].ore_type = MERIDINE
	_nodes[2].ore_type = KYRITE
	assert_eq(_place(0).crafted.number, 3, "the drill that mines it at full speed")
	assert_eq(_place(1).crafted.number, 5, "the faster of the soft drills")
	assert_eq(_place(2).crafted.number, 1, "the softest, the first by number on a tie")


func _place(index: int) -> Miner:
	return _nodes[index].place_miner(_player.miner_scene, _player.fleet, _player)


## The names of the ores whose badges `card`'s row `path` shows.
func _badges(card: UpgradeCard, path: String) -> Array[String]:
	var names: Array[String] = []
	for badge: Node in card.get_node(path).get_children():
		names.append(((badge as ItemBadge).item as OreType).display_name)
	return names
