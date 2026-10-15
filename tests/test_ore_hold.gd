extends GutTest
## The ship's hold in the cargo bay: a tank per ore, unknown ones dark, and its station card.

const TEST_MAP := preload("res://tests/support/test_map.gd")
const CATALOG: OreCatalog = preload("res://scenes/mining/ores/all_ores.tres")
const KYRITE: OreType = preload("res://scenes/mining/ores/ore_kyrite.tres")
const MERIDINE: OreType = preload("res://scenes/mining/ores/ore_meridine.tres")
const MIN_TEXT_HEIGHT: float = 0.02

var _map: Node3D
var _ship: Ship
var _hold: OreHold
var _player: Player


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_ship = _map.get_node("Ship") as Ship
	_hold = _ship.get_node("OreHold") as OreHold
	_player = _map.get_node("Player") as Player
	await wait_physics_frames(2)


func after_each() -> void:
	TranslationServer.set_locale("en")


func test_a_tank_per_ore() -> void:
	for ore_type: OreType in CATALOG.ores:
		assert_not_null(_hold.get_tank(ore_type), ore_type.display_name)
	assert_eq(_hold.get_parts().size(), CATALOG.ores.size())


func test_rarer_ores_get_smaller_tanks() -> void:
	var common: OreTank = _hold.get_tank(KYRITE)
	var signature: OreTank = _hold.get_tank(MERIDINE)
	assert_lt(signature.radius, common.radius)
	assert_lt(signature.height, common.height)


func test_the_lane_stays_clear() -> void:
	# The lane runs along the ship's x axis at z = 0 (ramp to lower deck); tanks keep to the banks.
	for ore_type: OreType in CATALOG.ores:
		var tank: OreTank = _hold.get_tank(ore_type)
		var z: float = _ship.to_local(tank.global_position).z
		assert_gte(absf(z) - tank.radius - 0.16, OreHold.LANE_WIDTH * 0.5, ore_type.display_name)


func test_unknown_until_brought_aboard() -> void:
	var tank: OreTank = _hold.get_tank(KYRITE)
	assert_false(tank.found)
	assert_eq((tank.get_node("Plate") as Label3D).text, "?")
	_ship.add_to_hold(KYRITE, 1500.0)
	assert_true(tank.found)
	assert_almost_eq(tank.fill_level(), 0.5, 0.001)
	assert_string_contains((tank.get_node("Plate") as Label3D).text, "1500")
	assert_true(_ship.pay({KYRITE: 1500}))
	assert_eq(tank.fill_level(), 0.0)
	assert_true(tank.found, "stays known when emptied")


func test_found_ores_are_saved() -> void:
	_ship.add_to_hold(MERIDINE, 10.0)
	assert_true(_ship.pay({MERIDINE: 10}))
	var data: Dictionary = SaveGame.ship_data(_ship)
	assert_has(data["found"] as Array, MERIDINE.resource_path)


func test_card_shows_the_selected_ore() -> void:
	_ship.add_to_hold(KYRITE, 42.0)
	assert_true(_hold.open(_player))
	_hold.select(_hold.get_tank(KYRITE))
	var card := _hold.card_menu as HoldCard
	assert_string_contains(_texts(card), "Kyrite")
	assert_string_contains(_texts(card), "42")
	_hold.select(_hold.get_tank(MERIDINE))
	assert_string_contains(_texts(card), "Unknown ore")
	assert_false(_texts(card).contains("Meridine"), "doesn't give the unknown ore away")
	_hold.close()


func test_camera_follows_the_selected_tank() -> void:
	assert_true(_hold.open(_player))
	_hold.select(_hold.get_tank(MERIDINE))
	var center: Vector3 = _hold.get_view_center()
	assert_lt(center.distance_to(_hold.get_tank(MERIDINE).global_position), 3.0)
	_hold.close()


func test_card_fits_and_reads_in_every_language() -> void:
	for ore_type: OreType in CATALOG.ores:
		_ship.add_to_hold(ore_type, 123456.0)
	assert_true(_hold.open(_player))
	var panel: WorldPanel = _hold.card
	var layout := Vector2(panel.size * panel.pixels_per_meter)
	for locale: String in SettingsMenu.languages():
		TranslationServer.set_locale(locale)
		for ore_type: OreType in CATALOG.ores:
			_hold.select(_hold.get_tank(ore_type))
			var needed: Vector2 = _hold.card_menu.get_combined_minimum_size()
			var label: String = "%s %s" % [locale, ore_type.display_name]
			assert_lte(needed.x, layout.x + 0.5, "%s: %s wide" % [label, needed.x])
			assert_lte(needed.y, layout.y + 0.5, "%s: %s high" % [label, needed.y])
	var text_height: float = 26.0 / panel.pixels_per_meter
	assert_gte(text_height / _hold.view_height, MIN_TEXT_HEIGHT)
	_hold.close()


func _texts(node: Node) -> String:
	var text: String = ""
	for label: Label in node.find_children("*", "Label", true, false):
		if label.is_visible_in_tree():
			text += label.text + "\n"
	return text
