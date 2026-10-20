extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")
const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const TANK: Upgrade = preload("res://game/progression/upgrades/miner_tank.tres")
const HOSE: Upgrade = preload("res://game/progression/upgrades/miner_hose.tres")
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
	assert_eq(station.selected.item, DRILL)
	assert_eq(station.selected.highlight, StationPart.Highlight.SELECTED)
	assert_true(station.card.visible)
	assert_eq((station.card_menu as UpgradeCard).upgrade, DRILL)


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
	_send(&"move_forward")
	assert_eq(station.selected.item, TANK, "up the miner")
	_send(&"move_forward")
	assert_eq(station.selected.item, HOSE)
	_send(&"move_forward")
	assert_eq(station.selected.item, HOSE, "nothing further up")
	_send(&"move_back")
	_send(&"move_back")
	assert_eq(station.selected.item, DRILL)
	assert_eq(station.get_part(HOSE).highlight, StationPart.Highlight.NONE)
	assert_eq((station.card_menu as UpgradeCard).upgrade, DRILL, "the card follows")


func test_interact_buys_the_selected_upgrade() -> void:
	var station: UpgradeStation = await _use("Miners")
	_ship.add_to_hold(KYRITE, 1000.0)
	_ship.add_to_hold(VYREL, 1000.0)
	_send(&"move_forward")
	_send(&"interact")
	assert_eq(_player.upgrades.mk(TANK), 2)
	assert_eq(_player.upgrades.mk(DRILL), 1)
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
	_ship.add_to_hold(KYRITE, 1000.0)
	_ship.add_to_hold(VYREL, 1000.0)
	await wait_seconds(0.5)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var tank: StationPart = station.get_part(TANK)
	_click(camera.unproject_position(tank.global_position))
	assert_eq(station.selected, tank)
	await wait_seconds(0.5)
	var button: Button = (station.card_menu as UpgradeCard).get_buy_button()
	_click(_on_card(station, button.get_global_rect().get_center()))
	assert_eq(_player.upgrades.mk(TANK), 2, "the card's button")


func test_weapon_station_lays_the_picked_weapon_on_the_bench() -> void:
	var station := await _use("Weapons") as WeaponStation
	assert_eq(station.bench_weapon, HARL)
	assert_eq(_items(station.get_parts()), HARL.parts as Array)
	assert_false(_rack_part(station, HARL).visible, "its rack slot is empty")
	_send(&"tab_next")
	assert_eq(station.bench_weapon, BRASK)
	assert_true(_rack_part(station, HARL).visible, "back on the rack")
	assert_eq(_items(station.get_parts()), [BRASK] + (BRASK.parts as Array), "not owned: build it")
	assert_eq(station.selected.item, BRASK)
	_send(&"tab_prev")
	_send(&"tab_prev")
	assert_eq(station.bench_weapon, DRAY, "wraps around")
	assert_eq(_items(station.get_parts()), DRAY.parts as Array)


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
	var station := _ship.get_node("Rooms/Lower/%s/UpgradeStation" % room) as UpgradeStation
	var use: Interactable = station.use_point
	_player.global_position = use.global_position + use.global_basis.z * 0.3
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_player.interact(), use, room)
	await wait_process_frames(1)
	return station


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


## Where a pixel of the station's card (layout size) shows on the screen.
func _on_card(station: Station, pixel: Vector2) -> Vector2:
	var panel: WorldPanel = station.card
	var uv: Vector2 = pixel / (panel.size * panel.pixels_per_meter)
	var at: Vector3 = panel.to_global(
		Vector3((uv.x - 0.5) * panel.size.x, (0.5 - uv.y) * panel.size.y, 0.0)
	)
	return get_viewport().get_camera_3d().unproject_position(at)
