extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")
const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")
const KITH: WeaponType = preload("res://game/weapons/types/kith/kith.tres")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const TANK: Upgrade = preload("res://game/progression/upgrades/miner_tank.tres")
const HOSE: Upgrade = preload("res://game/progression/upgrades/miner_hose.tres")
const PLATING: Upgrade = preload("res://game/progression/upgrades/miner_plating.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")

var _map: Node3D
var _player: Player
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func test_using_a_station_frames_it_and_selects_its_first_part() -> void:
	var station: UpgradeStation = await _use("Miners")
	assert_eq(_player.menu, station)
	assert_eq(WorldMenu.used_by(get_tree(), _player), station)
	assert_false(station.use_point.enabled, "nobody else can use it meanwhile")
	assert_almost_eq(_player.global_position.x, station.user_spot.global_position.x, 0.05)
	assert_almost_eq(_player.global_position.z, station.user_spot.global_position.z, 0.05)
	var bay := station as MinerBayStation
	assert_eq(station.selected, bay.get_miner_part(), "the miner on the pad")
	assert_eq(station.selected.highlight, StationPart.Highlight.SELECTED)
	assert_true(station.card.visible)
	assert_eq((station.card_menu as MinerCard).miner, _player.fleet.get_miner(1))


func test_a_station_is_used_from_any_side() -> void:
	for path: String in ["Miners/MinerBay", "Skills/SkillGraph", "Weapons/UpgradeStation"]:
		var station := _ship.get_node("Rooms/Lower/" + path) as Station
		var use: Interactable = station.use_point
		var half: Vector2 = use.footprint * 0.5
		var reach: float = use.interact_range - 0.2
		var sides: Dictionary[String, Vector3] = {
			"left": Vector3(-half.x - reach, 0.0, 0.0),
			"right": Vector3(half.x + reach, 0.0, 0.0),
			"behind": Vector3(0.0, 0.0, -half.y - reach),
			"in front": Vector3(0.0, 0.0, half.y + reach),
		}
		for side: String in sides:
			var at: Vector3 = use.to_global(sides[side])
			assert_almost_eq(use.distance_to(at), reach, 0.001, "%s %s" % [path, side])
			assert_eq(Interactable.nearest(get_tree(), at), use, "%s %s" % [path, side])
		var away: Vector3 = use.to_global(Vector3(half.x + use.interact_range + 0.2, 0.0, 0.0))
		assert_ne(Interactable.nearest(get_tree(), away), use, path + " out of reach")


func test_player_stands_still_while_using_a_station() -> void:
	await _use("Miners")
	var before: Vector3 = _player.global_position
	Input.action_press(&"move_right")
	await wait_physics_frames(20)
	Input.action_release(&"move_right")
	assert_almost_eq(_player.global_position.x, before.x, 0.01)
	assert_almost_eq(_player.global_position.z, before.z, 0.01)


func test_directions_move_the_highlight_between_parts() -> void:
	var station: UpgradeStation = await _use("Miners")
	# Directions go by the parts' places on the screen, once the camera framed the bay.
	await wait_seconds(0.5)
	station.select(station.get_part(DRILL))
	_send(&"move_forward")
	assert_eq(station.selected.item, TANK, "up the miner")
	_send(&"move_right")
	assert_eq(station.selected.item, PLATING, "its side boxes")
	station.select(station.get_part(TANK))
	_send(&"move_forward")
	assert_eq(station.selected.item, HOSE)
	_send(&"move_forward")
	assert_true(station.selected is MinerCradle, "further up: the cradles")
	station.select(station.get_part(HOSE))
	_send(&"move_back")
	_send(&"move_back")
	assert_eq(station.selected.item, DRILL)
	assert_eq(station.get_part(HOSE).highlight, StationPart.Highlight.NONE)
	assert_eq((station.card_menu as UpgradeCard).upgrade, DRILL, "the card follows")


func test_interact_buys_the_selected_upgrade() -> void:
	var station: UpgradeStation = await _use("Miners")
	_player.hold.add(KYRITE, 1000.0)
	_player.hold.add(VYREL, 1000.0)
	station.select(station.get_part(TANK))
	_send(&"interact")
	var levels: Upgrades = _miner_levels()
	assert_true(levels.is_running(TANK), "into the miner on the pad")
	levels.finish_all()
	assert_eq(levels.mk(TANK), 2)
	assert_eq(levels.mk(DRILL), 1)
	assert_eq(_player.upgrades.mk(TANK), 1, "not the player's own")
	assert_eq(station.user, _player, "buying doesn't close it")


func test_pause_and_cancel_close_the_station() -> void:
	for action: StringName in [&"pause", &"ui_cancel"]:
		var station: UpgradeStation = await _use("Armor")
		_send(action)
		assert_null(_player.menu, action)
		assert_null(station.user)
		assert_false(station.card.visible)
		assert_null(station.selected)
		assert_true(station.use_point.enabled)


func test_card_floats_beside_the_selected_part_facing_the_camera() -> void:
	var station: UpgradeStation = await _use("Miners")
	await wait_seconds(0.5)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var goal: Vector3 = station.selected.card_position(camera)
	assert_lt(station.card.global_position.distance_to(goal), 0.05)
	assert_almost_eq(station.card.global_basis.z.dot(camera.global_basis.z), 1.0, 0.001)
	var part: Vector2 = camera.unproject_position(station.selected.global_position)
	var card: Vector2 = camera.unproject_position(station.card.global_position)
	assert_gt(card.x, part.x, "to the right of the part")


func test_mouse_picks_parts_and_uses_the_card() -> void:
	var station: UpgradeStation = await _use("Miners")
	_player.hold.add(KYRITE, 1000.0)
	_player.hold.add(VYREL, 1000.0)
	await wait_seconds(0.5)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var tank: StationPart = station.get_part(TANK)
	_click(camera.unproject_position(tank.global_position))
	assert_eq(station.selected, tank)
	await wait_seconds(0.5)
	var button: Button = (station.card_menu as UpgradeCard).get_buy_button()
	_click(_on_card(station, button.get_global_rect().get_center()))
	assert_true(_miner_levels().is_running(TANK), "the card's button")
	_miner_levels().finish_all()
	assert_eq(_miner_levels().mk(TANK), 2)


## A real click spans frames, and the card refreshes every frame meanwhile.
func test_mouse_stops_a_level_under_way() -> void:
	var station: UpgradeStation = await _use("Miners")
	_player.hold.add(KYRITE, 1000.0)
	_player.hold.add(VYREL, 1000.0)
	station.select(station.get_part(DRILL))
	await wait_seconds(0.5)
	var card := station.card_menu as UpgradeCard
	var button: Button = card.get_buy_button()
	await _slow_click(_on_card(station, button.get_global_rect().get_center()))
	assert_true(_miner_levels().is_running(DRILL))
	for press: int in 2:
		await wait_process_frames(2)
		await _slow_click(_on_card(station, button.get_global_rect().get_center()))
	assert_false(_miner_levels().is_running(DRILL), "pressed twice")
	assert_eq(_player.hold.amount(KYRITE), 1000.0, "the whole cost back")


func test_weapon_station_lays_the_picked_weapon_on_the_bench() -> void:
	var station := await _use("Weapons") as WeaponStation
	assert_eq(station.bench_weapon, HARL)
	assert_eq(_items(station.get_parts()), HARL.parts as Array)
	assert_false(_rack_part(station, HARL).visible, "its rack slot is empty")
	station.lay_on_bench(BRASK)
	assert_eq(station.bench_weapon, BRASK)
	assert_true(_rack_part(station, HARL).visible, "back on the rack")
	assert_eq(_items(station.get_parts()), [BRASK] + (BRASK.parts as Array), "not owned: build it")
	assert_eq(station.selected.item, BRASK)
	_send(&"tab_next")
	assert_eq(station.bench_weapon, DRAY, "the first weapon of the next row")
	assert_eq(_items(station.get_parts()), DRAY.parts as Array)
	_send(&"tab_next")
	assert_eq(station.bench_weapon, KITH, "the prototypes' row")
	_send(&"tab_next")
	assert_eq(station.bench_weapon, HARL, "wraps around")


func test_weapon_station_shows_unowned_weapons_see_through() -> void:
	var station := await _use("Weapons") as WeaponStation
	assert_false(_player.arsenal.owns(BRASK))
	var mesh := _rack_part(station, BRASK).find_children("*", "GeometryInstance3D", true, false)[0]
	assert_gt((mesh as GeometryInstance3D).transparency, 0.0)
	mesh = _rack_part(station, DRAY).find_children("*", "GeometryInstance3D", true, false)[0]
	assert_eq((mesh as GeometryInstance3D).transparency, 0.0)


func test_mouse_picks_a_weapon_from_the_rack() -> void:
	var station := await _use("Weapons") as WeaponStation
	await wait_seconds(0.5)
	var camera: Camera3D = get_viewport().get_camera_3d()
	_click(camera.unproject_position(_rack_part(station, DRAY).global_position))
	assert_eq(station.bench_weapon, DRAY)


func _use(room: String) -> UpgradeStation:
	var station_name: String = "MinerBay" if room == "Miners" else "UpgradeStation"
	var station := _ship.get_node("Rooms/Lower/%s/%s" % [room, station_name]) as UpgradeStation
	var use: Interactable = station.use_point
	_player.global_position = station.user_spot.global_position
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_player.interact(), use, room)
	await wait_process_frames(1)
	return station


## The levels of M-01, the miner on the pad.
func _miner_levels() -> Upgrades:
	return _player.fleet.get_miner(1).upgrades


func _rack_part(station: WeaponStation, weapon_type: WeaponType) -> StationPart:
	for part: StationPart in station.get_rack_parts():
		if part.item == weapon_type:
			return part
	return null


func _items(parts: Array[StationPart]) -> Array[Resource]:
	var items: Array[Resource] = []
	for part: StationPart in parts:
		items.append(part.item)
	return items


## Presses and releases `action` as an input event.
func _send(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input(event)


func _click(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	get_viewport().push_input(move, true)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		get_viewport().push_input(click, true)


## A click held for a few frames, like a player's.
func _slow_click(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	get_viewport().push_input(move, true)
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		get_viewport().push_input(click, true)
		await wait_process_frames(3)


## Where a pixel of the station's card (layout size) shows on the screen.
func _on_card(station: Station, pixel: Vector2) -> Vector2:
	var panel: WorldPanel = station.card
	var uv: Vector2 = pixel / (panel.size * panel.pixels_per_meter)
	var at: Vector3 = panel.to_global(
		Vector3((uv.x - 0.5) * panel.size.x, (0.5 - uv.y) * panel.size.y, 0.0)
	)
	return get_viewport().get_camera_3d().unproject_position(at)
