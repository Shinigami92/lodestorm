extends GutTest
## The refinery in the cargo bay: four furnaces (cold until unlocked) and the ingot rack, their
## cards, starting and stopping batches, bars landing in the hold, and the way it keeps clear of
## the hold's silos.

const TEST_MAP := preload("res://tests/support/test_map.gd")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const ALLOYS: AlloyCatalog = preload("res://game/refinery/all_alloys.tres")
const COBREL: AlloyType = preload("res://game/refinery/alloys/alloy_cobrel.tres")
const MERISK: AlloyType = preload("res://game/refinery/alloys/alloy_merisk.tres")
const GANTRITE: AlloyType = preload("res://game/refinery/alloys/alloy_gantrite.tres")
const SELYX: OreType = preload("res://game/ores/types/ore_selyx.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
const MIN_TEXT_HEIGHT: float = 0.02

var _map: Node3D
var _ship: Ship
var _refinery: Refinery
var _furnace: FurnaceStation
var _rack: IngotRack
var _player: Player


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_ship = _map.get_node("Ship") as Ship
	_refinery = _ship.get_node("Refinery") as Refinery
	_furnace = _refinery.get_furnaces()[0]
	_rack = _refinery.get_node("IngotRack") as IngotRack
	_player = _map.get_node("Player") as Player
	await wait_physics_frames(2)


func after_each() -> void:
	TranslationServer.set_locale("en")


func test_four_furnaces_and_a_rack() -> void:
	var furnaces: Array[FurnaceStation] = _refinery.get_furnaces()
	assert_eq(furnaces.size(), Refining.SLOTS)
	for slot: int in furnaces.size():
		assert_eq(furnaces[slot].slot, slot)
	assert_eq(_rack.get_reading_order().size(), ALLOYS.alloys.size())
	for alloy: AlloyType in ALLOYS.alloys:
		assert_not_null(_rack.get_shelf(alloy), alloy.display_name)


func test_it_keeps_clear_of_the_silos_and_the_lane() -> void:
	var hold := _ship.get_node("OreHold") as OreHold
	var spots: Array[Node3D] = []
	spots.append_array(_refinery.get_furnaces())
	spots.append(_rack)
	for spot: Node3D in spots:
		var at: Vector3 = _ship.to_local(spot.global_position)
		assert_gt(at.z - 1.0, OreHold.LANE_WIDTH * 0.5, "%s off the lane" % spot.name)
		for tank: OreTank in hold.get_parts():
			var apart: Vector3 = tank.global_position - spot.global_position
			var gap: float = Vector2(apart.x, apart.z).length() - tank.radius - 1.2
			assert_gt(gap, 0.0, "%s and %s" % [spot.name, tank.name])


func test_a_way_between_the_wall_and_the_left_furnace() -> void:
	# The cargo bay's inner wall by the lower deck is at ship x -3.
	var left: FurnaceStation = _refinery.get_furnaces()[0]
	var edge: float = _ship.to_local(left.global_position).x - FurnaceStation.WIDTH * 0.5 - 0.08
	assert_gte(edge - -3.0, OreHold.WALK_WIDTH, "room to walk past")
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.exclude = [_player.get_rid()]
	var space: PhysicsDirectSpaceState3D = _ship.get_world_3d().direct_space_state
	var at: Vector3 = _ship.to_local(left.global_position)
	for z: float in [at.z - 1.5, at.z, at.z + 1.5]:
		var middle := Vector3((edge - 3.0) * 0.5, 2.5 + 1.0, z)
		query.transform = Transform3D(Basis.IDENTITY, _ship.to_global(middle))
		assert_eq(space.intersect_shape(query).size(), 0, "free at z %s" % z)


func test_a_locked_furnace_is_cold() -> void:
	assert_false(_furnace.is_unlocked())
	assert_true(_furnace.open(_player))
	var card := _furnace.card_menu as FurnaceCard
	assert_string_contains(_texts(card), "This furnace is cold.")
	assert_false(card.get_action_button().is_visible_in_tree())
	assert_false(card.press_primary())
	_furnace.close()


func test_unknown_recipes_give_nothing_away() -> void:
	_ship.furnaces.unlock()
	_player.hold.add(KYRITE, 50.0)
	assert_true(_furnace.open(_player))
	_furnace.recipe = COBREL
	_furnace.refresh()
	var card := _furnace.card_menu as FurnaceCard
	assert_string_contains(_texts(card), "Unknown alloy")
	assert_false(_texts(card).contains("Cobrel"))
	assert_false(_texts(card).contains("Vyrel"), "only the ores found so far")
	assert_true(card.get_action_button().disabled)
	_furnace.close()


func test_starting_a_batch() -> void:
	_ship.furnaces.unlock()
	_player.hold.add(KYRITE, 100.0)
	_player.hold.add(VYREL, 100.0)
	assert_true(_furnace.open(_player))
	assert_eq(_furnace.recipe, COBREL, "starts on a known recipe")
	var card := _furnace.card_menu as FurnaceCard
	assert_string_contains(_texts(card), "Cobrel")
	_furnace.step_bars(4)
	assert_eq(_furnace.get_bars(), 5)
	assert_string_contains(_texts(card), "5:00", "takes five minutes")
	assert_false(card.get_action_button().disabled)
	assert_true(card.press_primary())
	var batch: AlloyBatch = _player.refining.get_batch(0)
	assert_eq(batch.alloy, COBREL)
	assert_eq(batch.bars, 5)
	assert_eq(_player.hold.amount(KYRITE), 50.0)
	assert_string_contains(_texts(card), "Bars done: 0 / 5")
	assert_eq(card.get_action_button().text, "Stop")
	_furnace.close()


func test_bars_go_up_to_what_the_hold_pays_for() -> void:
	_ship.furnaces.unlock()
	_player.hold.add(KYRITE, 73.0)
	_player.hold.add(VYREL, 100.0)
	assert_true(_furnace.open(_player))
	var card := _furnace.card_menu as FurnaceCard
	assert_true(card.get_bar_button(-1).disabled, "at least one")
	card.get_bar_button(5).pressed.emit()
	assert_eq(_furnace.get_bars(), 6)
	card.get_bar_button(10).pressed.emit()
	assert_eq(_furnace.get_bars(), 7, "the hold pays for seven")
	assert_true(card.get_bar_button(1).disabled)
	card.get_bar_button(-10).pressed.emit()
	assert_eq(_furnace.get_bars(), 1)
	card.get_bar_button(1).pressed.emit()
	assert_eq(_furnace.get_bars(), 2)
	var minus := InputEventAction.new()
	minus.action = &"zoom_out"
	minus.pressed = true
	assert_true(_furnace._shortcut(minus))
	assert_eq(_furnace.get_bars(), 1, "zoom_out takes one off")
	_furnace.close()


func test_tab_steps_through_the_recipes_by_tier() -> void:
	_ship.furnaces.unlock()
	assert_true(_furnace.open(_player))
	_furnace.recipe = ALLOYS.alloys[0]
	_furnace._cycle(1)
	assert_eq(_furnace.recipe, ALLOYS.alloys[1])
	_furnace._cycle(-2)
	assert_eq(_furnace.recipe, ALLOYS.alloys[-1], "wraps around")
	_furnace.close()


func test_wasd_moves_across_the_cargo_bay() -> void:
	_ship.furnaces.unlock()
	var hold := _ship.get_node("OreHold") as OreHold
	var furnaces: Array[FurnaceStation] = _refinery.get_furnaces()
	assert_true(_rack.open(_player))
	_rack.select(_rack.get_shelf(GANTRITE))
	await _settle_camera()
	_rack.step(Vector2.LEFT)
	assert_eq(_rack.selected, _rack.get_shelf(COBREL))
	_rack.step(Vector2.LEFT)
	assert_null(_rack.user, "handed over")
	assert_eq(furnaces[-1].user, _player, "the right furnace")
	assert_eq(_player.menu, furnaces[-1])
	await _settle_camera()
	furnaces[-1].step(Vector2.LEFT)
	assert_eq(furnaces[-2].user, _player)
	var recipe: AlloyType = furnaces[-2].recipe
	var bars: int = furnaces[-2].get_bars()
	await _settle_camera()
	furnaces[-2].step(Vector2.RIGHT)
	assert_eq(furnaces[-2].recipe, recipe, "the directions never pick a recipe")
	assert_eq(furnaces[-2].get_bars(), bars, "nor the bars")
	assert_eq(furnaces[-1].user, _player)
	await _settle_camera()
	furnaces[-1].step(Vector2.RIGHT)
	assert_eq(_rack.user, _player, "back on the rack")
	for shelf: AlloyType in [COBREL, GANTRITE]:
		hold.close()
		_rack.close()
		assert_true(_rack.open(_player))
		_rack.select(_rack.get_shelf(shelf))
		await _settle_camera()
		_rack.step(Vector2.UP)
		assert_eq(hold.user, _player, "%s up: the silos" % shelf.display_name)
		assert_eq(hold.selected, hold.get_tank(SELYX), "%s up: Selyx" % shelf.display_name)
	hold.close()


func test_wasd_skips_a_station_someone_else_uses() -> void:
	var other: Player = PLAYER_SCENE.instantiate() as Player
	other.local = false
	_map.add_child(other)
	await wait_physics_frames(1)
	assert_true(_furnace.open(other))
	var hold := _ship.get_node("OreHold") as OreHold
	assert_false(hold.room_parts(_player).has(_furnace.get_parts()[0]))
	assert_true(hold.room_parts(_player).has(_rack.get_shelf(COBREL)))
	_furnace.close()


func test_stopping_needs_a_second_press() -> void:
	_ship.furnaces.unlock()
	_player.hold.add(KYRITE, 100.0)
	_player.hold.add(VYREL, 100.0)
	assert_true(_furnace.open(_player))
	_furnace.step_bars(3)
	assert_true(_furnace.start())
	var card := _furnace.card_menu as FurnaceCard
	assert_false(card.press_primary(), "the first press asks")
	assert_not_null(_player.refining.get_batch(0))
	assert_true(card.get_status().visible)
	assert_true(card.press_primary())
	assert_null(_player.refining.get_batch(0))
	assert_eq(_player.hold.amount(KYRITE), 100.0, "the ore of every unfinished bar is back")
	_furnace.close()


func test_nothing_starts_during_a_mission() -> void:
	_ship.furnaces.unlock()
	_player.hold.add(KYRITE, 100.0)
	_player.hold.add(VYREL, 100.0)
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	assert_true((_map.get_node("Mission") as Mission).is_underway())
	await wait_process_frames(1)
	assert_true(_furnace.open(_player))
	assert_false(_furnace.can_start())
	assert_string_contains(_texts(_furnace.card_menu), "Locked until everyone is back aboard.")
	_furnace.close()


func test_a_running_furnace_glows_in_its_alloys_color() -> void:
	_ship.furnaces.unlock()
	var fill := _furnace.get_node("Fill/Level") as MeshInstance3D
	await wait_process_frames(1)
	assert_false(fill.visible)
	_player.hold.add(KYRITE, 100.0)
	_player.hold.add(VYREL, 100.0)
	assert_true(
		_player.refining.start(0, COBREL, 2, _player.hold, Time.get_unix_time_from_system())
	)
	await wait_process_frames(1)
	assert_true(fill.visible)
	assert_eq(fill.material_override, COBREL.get_glow_material())
	assert_string_contains((_furnace.get_node("Plate") as Label3D).text, "0 / 2")


func test_finished_bars_land_in_the_hold_and_on_the_rack() -> void:
	_player.hold.add(KYRITE, 100.0)
	_player.hold.add(VYREL, 100.0)
	var now: float = Time.get_unix_time_from_system()
	assert_true(_player.refining.start(2, COBREL, 3, _player.hold, now))
	_refinery.tick(now + COBREL.seconds_per_bar * 2.2)
	assert_eq(_player.hold.amount(COBREL), 2.0)
	await wait_process_frames(1)
	var shelf: RackShelf = _rack.get_shelf(COBREL)
	assert_true(shelf.known)
	assert_eq(shelf.count, 2)
	assert_eq(shelf.shown_bars(), 2)
	assert_string_contains((shelf.get_node("Plate") as Label3D).text, "2")


func test_the_rack_shows_unknown_alloys_dark() -> void:
	await wait_process_frames(1)
	var shelf: RackShelf = _rack.get_shelf(MERISK)
	assert_false(shelf.known)
	assert_eq((shelf.get_node("Plate") as Label3D).text, "?")
	_player.hold.add(MERISK, 40.0)
	assert_true(shelf.known)
	assert_eq(shelf.shown_bars(), RackShelf.SHOWN_BARS, "stacks up to a limit")
	assert_string_contains((shelf.get_node("Plate") as Label3D).text, "40")


func test_rack_card_shows_the_alloy_and_its_recipe() -> void:
	_player.hold.add(COBREL, 12.0)
	_player.hold.mark_found(KYRITE)
	assert_true(_rack.open(_player))
	_rack.select(_rack.get_shelf(COBREL))
	var card := _rack.card_menu as RackCard
	assert_string_contains(_texts(card), "Cobrel")
	assert_string_contains(_texts(card), "In the rack: 12")
	assert_string_contains(_texts(card), "Kyrite")
	assert_string_contains(_texts(card), "Vyrel")
	_rack.select(_rack.get_shelf(MERISK))
	assert_string_contains(_texts(card), "Unknown alloy")
	assert_false(_texts(card).contains("Merisk"))
	assert_false(_texts(card).contains("Pallin"), "only the ores found so far")
	_rack._cycle(1)
	assert_ne(_rack.selected, _rack.get_shelf(MERISK))
	_rack.close()


func test_they_show_the_users_batches_and_hold() -> void:
	_ship.furnaces.unlock()
	var other: Player = PLAYER_SCENE.instantiate() as Player
	other.local = false
	_map.add_child(other)
	await wait_physics_frames(1)
	other.hold.add(KYRITE, 100.0)
	other.hold.add(VYREL, 100.0)
	other.hold.add(MERISK, 3.0)
	other.refining.start(0, COBREL, 1, other.hold, Time.get_unix_time_from_system())
	await wait_process_frames(1)
	assert_null(_furnace.get_batch(), "the viewer's while nobody uses it")
	assert_false(_rack.get_shelf(MERISK).known)
	_furnace.open(other)
	assert_not_null(_furnace.get_batch(), "the user's")
	_furnace.close()
	_rack.open(other)
	await wait_process_frames(1)
	assert_true(_rack.get_shelf(MERISK).known)
	_rack.close()


func test_cards_fit_and_read_in_every_language() -> void:
	for furnaces: int in Refining.SLOTS:
		_ship.furnaces.unlock()
	_player.hold.add(KYRITE, 123456.0)
	_player.hold.add(VYREL, 123456.0)
	for alloy: AlloyType in ALLOYS.alloys:
		for ore_type: OreType in alloy.recipe:
			_player.hold.add(ore_type, 123456.0)
		_player.hold.add(alloy, 123456.0)
	var running: FurnaceStation = _refinery.get_furnaces()[1]
	var now: float = Time.get_unix_time_from_system()
	_player.refining.start(1, ALLOYS.alloys[-1], 9999, _player.hold, now)
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		assert_true(_furnace.open(_player))
		for alloy: AlloyType in ALLOYS.alloys:
			_furnace.recipe = alloy
			for bars: int in [1, 50, 9999] as Array[int]:
				_furnace.bars = bars
				_furnace.refresh()
				_assert_card_fits(_furnace, "%s %s %d" % [locale, alloy.display_name, bars])
		_furnace.close()
		assert_true(running.open(_player))
		running.stop()
		running.refresh()
		_assert_card_fits(running, "%s running" % locale)
		running.close()
		assert_true(_rack.open(_player))
		for shelf: StationPart in _rack.get_reading_order():
			_rack.select(shelf)
			_assert_card_fits(_rack, "%s %s" % [locale, shelf.name])
		_rack.close()
	for station: Station in [_furnace, _rack] as Array[Station]:
		var text_height: float = 26.0 / station.card.pixels_per_meter
		assert_gte(text_height / station.view_height, MIN_TEXT_HEIGHT, station.name)


## Puts the camera where it frames the menu now (it glides there while playing).
func _settle_camera() -> void:
	(_map.get_node("IsoCameraRig") as IsoCameraRig).snap()
	await wait_process_frames(2)


func _assert_card_fits(station: Station, label: String) -> void:
	var panel: WorldPanel = station.card
	var layout := Vector2(panel.size * panel.pixels_per_meter)
	var needed: Vector2 = station.card_menu.get_combined_minimum_size()
	assert_lte(needed.x, layout.x + 0.5, "%s: %s wide" % [label, needed.x])
	assert_lte(needed.y, layout.y + 0.5, "%s: %s high" % [label, needed.y])


func _texts(node: Node) -> String:
	var text: String = ""
	for label: Label in node.find_children("*", "Label", true, false):
		if label.is_visible_in_tree():
			text += label.text + "\n"
	for button: Button in node.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			text += button.text + "\n"
	return text
