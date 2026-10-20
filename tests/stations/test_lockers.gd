extends GutTest
## The lockers in the armory, where each player picks their loadout.

const TEST_MAP := preload("res://tests/support/test_map.gd")
const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")

var _map: Node3D
var _player: Player
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	_ship.ramp_duration = 0.25
	await wait_physics_frames(2)


func test_locker_assigns_slots() -> void:
	var locker: LoadoutStation = await _open_locker()
	var card := locker.card_menu as LoadoutCard
	_select(locker, DRAY)
	assert_eq(card.weapon_type, DRAY)
	assert_false(card.get_slot_button(0).button_pressed)
	assert_true(card.get_slot_button(1).button_pressed, "Dray is in slot 2")
	assert_eq(locker.selected_slot, 0)
	assert_true(card.press_primary(), "interact puts it into the selected slot")
	assert_eq(_player.loadout.weapons, [DRAY, HARL] as Array[WeaponType], "swapped")
	await wait_process_frames(1)
	assert_true(card.get_slot_button(0).button_pressed)
	assert_true(card.press_primary())
	assert_null(_player.loadout.get_weapon(0), "again takes it out")
	card.get_slot_button(1).pressed.emit()
	assert_eq(_player.loadout.get_weapon(1), DRAY, "the card's slot buttons")


func test_locker_tabs_between_slots() -> void:
	var locker: LoadoutStation = await _open_locker()
	_send(&"tab_next")
	assert_eq(locker.selected_slot, 1)
	_send(&"tab_next")
	assert_eq(locker.selected_slot, 0, "wraps around")
	_select(locker, HARL)
	_send(&"tab_next")
	_send(&"interact")
	assert_eq(_player.loadout.weapons, [DRAY, HARL] as Array[WeaponType])


func test_locker_lays_the_loadout_in_its_cradles() -> void:
	var locker: LoadoutStation = await _open_locker()
	var cradle_1 := locker.get_node("Cradle1") as Node3D
	var cradle_2 := locker.get_node("Cradle2") as Node3D
	var near := Vector3.ONE * 0.01
	assert_almost_eq(locker.get_part(HARL).global_position, cradle_1.global_position, near)
	assert_almost_eq(locker.get_part(DRAY).global_position, cradle_2.global_position, near)
	assert_true(locker.toggle(HARL, 0))
	await wait_process_frames(1)
	var hanging: Vector3 = locker.get_part(HARL).global_position
	assert_gt(hanging.y, cradle_1.global_position.y + 0.5, "back up where it hangs")


func test_locker_shows_locked_weapons() -> void:
	var locker: LoadoutStation = await _open_locker()
	var card := locker.card_menu as LoadoutCard
	_select(locker, BRASK)
	assert_true(card.get_slot_button(0).disabled, "not owned yet")
	assert_false(locker.toggle(BRASK, 0))
	_player.arsenal.unlock(BRASK)
	await wait_process_frames(2)
	assert_false(card.get_slot_button(0).disabled)
	assert_true(card.press_primary())
	assert_eq(_player.loadout.get_weapon(0), BRASK)


func test_locker_locks_while_a_mission_is_underway() -> void:
	var locker: LoadoutStation = await _open_locker()
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_process_frames(2)
	assert_true(locker.is_locked())
	assert_true((locker.get_node("Door") as Node3D).visible, "the door is shut")
	assert_false(locker.toggle(DRAY, 0))
	assert_eq(_player.loadout.get_weapon(0), HARL, "unchanged")


func test_each_player_has_their_own_locker() -> void:
	var lockers: Array[LoadoutStation] = []
	for i: int in 4:
		lockers.append(_ship.get_node("Rooms/Lower/Armory/Locker%d" % (i + 1)) as LoadoutStation)
	assert_eq(lockers[0].get_owner_player(), _player)
	assert_true(lockers[0].can_use(_player))
	assert_false(lockers[1].can_use(_player), "another player's")
	await wait_process_frames(1)
	assert_true((lockers[1].get_node("Door") as Node3D).visible, "shut without its player")
	assert_false((lockers[0].get_node("Door") as Node3D).visible)
	lockers[1].use_point.use(_player)
	assert_null(lockers[1].user)


func _open_locker() -> LoadoutStation:
	var locker := _ship.get_node("Rooms/Lower/Armory/Locker1") as LoadoutStation
	var use: Interactable = locker.use_point
	_player.global_position = use.global_position + use.global_basis.z * 0.3
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_player.interact(), use)
	assert_eq(locker.user, _player)
	await wait_process_frames(1)
	return locker


func _select(locker: LoadoutStation, weapon_type: WeaponType) -> void:
	locker.select(locker.get_part(weapon_type))


## Presses and releases `action` as an input event.
func _send(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input(event)


func test_mouse_puts_a_weapon_into_slot_2() -> void:
	var locker: LoadoutStation = await _open_locker()
	_player.arsenal.unlock(BRASK)
	await wait_seconds(0.5)
	var camera: Camera3D = get_viewport().get_camera_3d()
	await _click(camera.unproject_position(locker.get_part(BRASK).global_position))
	assert_eq(locker.selected.item, BRASK)
	await wait_seconds(0.5)
	var button: Button = (locker.card_menu as LoadoutCard).get_slot_button(1)
	await _click(_on_card(locker, button.get_global_rect().get_center()))
	assert_eq(_player.loadout.get_weapon(1), BRASK)


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
		await wait_process_frames(1)


## Where a pixel of the station's card (layout size) shows on the screen.
func _on_card(station: Station, pixel: Vector2) -> Vector2:
	var panel: WorldPanel = station.card
	var uv: Vector2 = pixel / (panel.size * panel.pixels_per_meter)
	var at: Vector3 = panel.to_global(
		Vector3((uv.x - 0.5) * panel.size.x, (0.5 - uv.y) * panel.size.y, 0.0)
	)
	return get_viewport().get_camera_3d().unproject_position(at)


func test_locker_keeps_one_weapon_in_the_loadout() -> void:
	var locker: LoadoutStation = await _open_locker()
	assert_true(locker.toggle(DRAY, 1))
	assert_eq(_player.loadout.get_weapon(1), null)
	assert_false(locker.toggle(HARL, 0), "the last one stays")
	assert_eq(_player.loadout.get_weapon(0), HARL)
	assert_true(locker.toggle(DRAY, 0), "swapping it out still works")
	assert_eq(_player.loadout.get_weapon(0), DRAY)


func test_keys_1_and_2_put_the_selected_weapon_into_that_slot() -> void:
	var locker: LoadoutStation = await _open_locker()
	_player.arsenal.unlock(BRASK)
	_select(locker, BRASK)
	_send(&"slot_2")
	assert_eq(locker.selected_slot, 1)
	assert_eq(_player.loadout.weapons, [HARL, BRASK] as Array[WeaponType])
	_send(&"slot_1")
	assert_eq(locker.selected_slot, 0)
	assert_eq(_player.loadout.weapons, [BRASK, HARL] as Array[WeaponType], "swapped")
	_send(&"slot_1")
	assert_eq(_player.loadout.weapons, [null, HARL] as Array[WeaponType], "again takes it out")
