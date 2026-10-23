extends GutTest
## The hold in the cargo bay: a silo per ore in clusters, unknown ones dark, used directly, and its
## station card; it shows the hold of the player using it, else the viewer's.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const CATALOG: OreCatalog = preload("res://game/ores/all_ores.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")
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
	# The main lane runs along the ship's x axis at z = 0 (ramp to lower deck); silos keep out of it.
	for ore_type: OreType in CATALOG.ores:
		var tank: OreTank = _hold.get_tank(ore_type)
		var z: float = _ship.to_local(tank.global_position).z
		assert_gte(absf(z) - tank.radius - 0.14, OreHold.LANE_WIDTH * 0.5, ore_type.display_name)


func test_clusters_leave_a_way_between_them() -> void:
	var clusters: Array[Array] = _hold.get_clusters()
	assert_eq(clusters.size(), 3, "one per band")
	for i: int in clusters.size():
		for j: int in range(i + 1, clusters.size()):
			for a: OreTank in clusters[i]:
				for b: OreTank in clusters[j]:
					var apart: float = (
						Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length()
					)
					var gap: float = apart - a.radius - b.radius - 0.28
					assert_gte(gap, OreHold.WALK_WIDTH, "%s and %s" % [a.name, b.name])


func test_no_silo_hides_another_ones_window_or_amount() -> void:
	# The camera looks along the hold's -Z: a silo in front must not cover a window behind it.
	for a: OreTank in _hold.get_parts():
		for b: OreTank in _hold.get_parts():
			if a == b or a.position.z <= b.position.z or a.position.z - b.position.z > 6.0:
				continue
			var needed: float = a.radius + b.radius * OreTank.WINDOW_WIDTH
			assert_gte(
				absf(a.position.x - b.position.x) + 0.001, needed, "%s hides %s" % [a.name, b.name]
			)
	# The camera looks along the hold's -Z and down at its pitch: the line of sight from each
	# amount's text towards it passes over the silos in front (their bodies as cylinders).
	var rise: float = tan(deg_to_rad(IsoCameraSettings.new().pitch))
	for b: OreTank in _hold.get_parts():
		var text: Vector3 = _hold.to_local((b.get_node("Amount") as Node3D).global_position)
		for a: OreTank in _hold.get_parts():
			var reach: float = a.radius + 0.12
			var dx: float = absf(a.position.x - text.x)
			if a == b or a.position.z <= b.position.z or dx >= reach:
				continue
			var enters: float = maxf(a.position.z - sqrt(reach * reach - dx * dx), text.z)
			var sight: float = text.y + (enters - text.z) * rise
			assert_gt(sight, a.position.y + a.height * 0.5, "%s hides %s" % [a.name, b.name])


func test_the_way_to_the_lift_stays_clear() -> void:
	# The lift's gate is in the cargo bay's back left corner (ship x -2.5..1.5, z -9.25).
	for ore_type: OreType in CATALOG.ores:
		var tank: OreTank = _hold.get_tank(ore_type)
		var at: Vector3 = _ship.to_local(tank.global_position)
		if at.z < 0.0:
			assert_gte(at.x - tank.radius - 0.14, 0.25, ore_type.display_name)


func test_the_ramp_button_stays_reachable() -> void:
	var button: Vector3 = _ship.to_local((_ship.get_node("RampButton") as Node3D).global_position)
	for ore_type: OreType in CATALOG.ores:
		var tank: OreTank = _hold.get_tank(ore_type)
		var at: Vector3 = _ship.to_local(tank.global_position)
		var apart: float = Vector2(at.x - button.x, at.z - button.z).length()
		assert_gte(apart - tank.radius - 0.14, 2.0, ore_type.display_name)


func test_using_a_silo_opens_the_hold_with_it() -> void:
	var tank: OreTank = _hold.get_tank(MERIDINE)
	_player.global_position = tank.use_point.global_position + Vector3(0.0, 0.0, tank.radius + 0.6)
	await wait_physics_frames(2)
	assert_eq(Interactable.nearest(get_tree(), _player.global_position), tank.use_point)
	tank.use_point.use(_player)
	assert_eq(_hold.user, _player)
	assert_eq(_hold.selected, tank)
	assert_false(_hold.get_tank(KYRITE).use_point.enabled, "nobody else can use it meanwhile")
	_hold.close()
	assert_true(_hold.get_tank(KYRITE).use_point.enabled)


func test_tab_reads_from_the_back_left() -> void:
	var order: Array[StationPart] = _hold.get_reading_order()
	assert_eq(order.size(), CATALOG.ores.size())
	for i: int in range(1, order.size()):
		var before: Vector3 = order[i - 1].position
		var now: Vector3 = order[i].position
		if absf(now.z - before.z) < 1.2:
			assert_gt(now.x, before.x, "left to right within a row: %s" % order[i].name)
		else:
			assert_gt(now.z, before.z, "rows from the back: %s" % order[i].name)
	assert_true(_hold.open(_player))
	_hold.select(order[0])
	_hold._cycle(1)
	assert_eq(_hold.selected, order[1])
	_hold._cycle(-2)
	assert_eq(_hold.selected, order[-1], "wraps around")
	_hold.close()


func test_silos_block_the_way() -> void:
	var tank: OreTank = _hold.get_tank(KYRITE)
	assert_not_null(tank.get_node_or_null("Body") as StaticBody3D)


func test_unknown_until_brought_aboard() -> void:
	var tank: OreTank = _hold.get_tank(KYRITE)
	var amount := tank.get_node("Amount") as Label3D
	var ore_name := tank.get_node("Name") as Label3D
	assert_false(tank.found)
	assert_eq(amount.text, "?")
	assert_eq(ore_name.text, "", "an unknown ore stays nameless")
	_player.hold.add(KYRITE, 1500.0)
	assert_true(tank.found)
	assert_almost_eq(tank.fill_level(), 0.5, 0.001)
	assert_eq(amount.text, "1500")
	assert_almost_eq(amount.modulate.h, KYRITE.color.h, 0.001, "in the ore's color")
	assert_eq(ore_name.text, KYRITE.get_display_name().to_upper())
	assert_true(_player.hold.pay({KYRITE: 1500}))
	assert_eq(tank.fill_level(), 0.0)
	assert_eq(amount.text, "0")
	assert_true(tank.found, "stays known when emptied")


func test_amounts_read_from_the_camera_and_fit() -> void:
	# Four digits on the smallest silo's display: big enough from the normal camera.
	const READABLE: float = 0.35
	for ore_type: OreType in CATALOG.ores:
		_player.hold.add(ore_type, 2480.0)
		var tank: OreTank = _hold.get_tank(ore_type)
		assert_gte(tank.amount_text_height(), READABLE, ore_type.display_name)
	_player.hold.add(KYRITE, 1000000.0)
	var amount := _hold.get_tank(KYRITE).get_node("Amount") as Label3D
	var width: float = (
		amount.font.get_string_size(amount.text, HORIZONTAL_ALIGNMENT_LEFT, -1, amount.font_size).x
		* amount.pixel_size
	)
	assert_lte(width, _hold.get_tank(KYRITE).radius * 2.0 * OreTank.DISPLAY_WIDTH, "long ones fit")


func test_silos_show_the_users_hold() -> void:
	var other: Player = PLAYER_SCENE.instantiate() as Player
	other.local = false
	_map.add_child(other)
	await wait_physics_frames(1)
	_player.hold.add(KYRITE, 10.0)
	other.hold.add(KYRITE, 500.0)
	other.hold.add(MERIDINE, 20.0)
	await wait_process_frames(1)
	assert_eq(_hold.get_shown_hold(), _player.hold, "the viewer's while nobody uses them")
	assert_eq(_hold.get_tank(KYRITE).amount, 10.0)
	assert_false(_hold.get_tank(MERIDINE).found)
	_hold.select(_hold.get_tank(KYRITE))
	_hold.open(other)
	await wait_process_frames(1)
	assert_eq(_hold.get_tank(KYRITE).amount, 500.0, "the user's")
	assert_true(_hold.get_tank(MERIDINE).found)
	_hold.close()
	await wait_process_frames(1)
	assert_eq(_hold.get_tank(KYRITE).amount, 10.0, "the viewer's again")
	assert_false(_hold.get_tank(MERIDINE).found)


func test_found_ores_are_saved() -> void:
	_player.hold.add(MERIDINE, 10.0)
	assert_true(_player.hold.pay({MERIDINE: 10}))
	var data: Dictionary = SaveGame.player_data(_player)
	assert_has(data["found"] as Array, ResourceUID.path_to_uid(MERIDINE.resource_path))


func test_card_shows_the_selected_ore() -> void:
	_player.hold.add(KYRITE, 42.0)
	assert_true(_hold.open(_player))
	_hold.select(_hold.get_tank(KYRITE))
	var card := _hold.card_menu as HoldCard
	assert_string_contains(_texts(card), "Kyrite")
	assert_string_contains(_texts(card), "42")
	assert_false(_texts(card).contains("drill"), "any drill mines it at full speed")
	_hold.select(_hold.get_tank(MERIDINE))
	assert_string_contains(_texts(card), "Unknown ore")
	assert_false(_texts(card).contains("Meridine"), "doesn't give the unknown ore away")
	assert_false(_texts(card).contains("drill"))
	_player.hold.add(MERIDINE, 5.0)
	_hold.select(_hold.get_tank(MERIDINE))
	assert_string_contains(_texts(card), "Full speed with drill MK3.")
	# Found in more regions than fit, with every body open: names the bodies instead.
	_ship.heat_shield.mk = _ship.heat_shield.max_mk()
	assert_gt(_hold.regions_with(KYRITE).size(), HoldCard.MAX_REGIONS, "a common ore")
	_hold.select(_hold.get_tank(KYRITE))
	assert_string_contains(_texts(card), "Found on: ")
	for body: CelestialBody in _hold.bodies_with(KYRITE):
		assert_string_contains(_texts(card), body.display_name)
	for region: Region in _hold.regions_with(KYRITE):
		assert_false(_texts(card).contains(region.display_name), region.display_name)
	_hold.close()


func test_ramp_countdown_hides_while_used() -> void:
	assert_true(_hold.open(_player))
	await wait_process_frames(2)
	assert_false((_ship.get_node("Countdown") as Label3D).visible)
	_hold.close()
	await wait_process_frames(2)
	assert_true((_ship.get_node("Countdown") as Label3D).visible)


func test_camera_follows_the_selected_tank() -> void:
	assert_true(_hold.open(_player))
	_hold.select(_hold.get_tank(MERIDINE))
	var center: Vector3 = _hold.get_view_center()
	assert_lt(center.distance_to(_hold.get_tank(MERIDINE).global_position), 3.0)
	_hold.close()


func test_card_fits_and_reads_in_every_language() -> void:
	for ore_type: OreType in CATALOG.ores:
		_player.hold.add(ore_type, 123456.0)
	# Every body open: the most places the card can name.
	_ship.heat_shield.mk = _ship.heat_shield.max_mk()
	assert_true(_hold.open(_player))
	var panel: WorldPanel = _hold.card
	var layout := Vector2(panel.size * panel.pixels_per_meter)
	for locale: String in SettingsList.languages():
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
