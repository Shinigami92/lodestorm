extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")
## In front of the settings terminal in cabin 1 (ship-local).
const AT_TERMINAL := Vector3(-48.6, 7.5, -12.9)

var _map: Node3D
var _player: Player
var _terminal: Terminal
var _panel: WorldPanel


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	var ship: Ship = _map.get_node("Ship") as Ship
	_terminal = ship.get_node("Rooms/Upper/Cabin1/Terminal") as Terminal
	_panel = _terminal.panel
	_player.global_position = ship.to_global(AT_TERMINAL)
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)


func after_each() -> void:
	for action: StringName in [&"interact", &"move_right", &"attack"]:
		Input.action_release(action)
	TranslationServer.set_locale("en")


func test_using_the_terminal_opens_its_menu() -> void:
	assert_eq(_player.interact(), _terminal)
	assert_eq(_panel.user, _player)
	assert_eq(_player.menu, _panel)
	assert_eq(WorldMenu.used_by(get_tree(), _player), _panel)
	assert_false(_terminal.enabled, "nobody else can use it meanwhile")
	assert_true(_panel.content is SettingsMenu)
	assert_eq(_focused().name, &"en", "the first control has the focus")


func test_player_stands_still_while_using_a_menu() -> void:
	_player.interact()
	var before: Vector3 = _player.global_position
	Input.action_press(&"move_right")
	await wait_physics_frames(20)
	assert_almost_eq(_player.global_position.x, before.x, 0.01)
	assert_almost_eq(_player.global_position.z, before.z, 0.01)


func test_movement_and_interact_steer_the_menu() -> void:
	_player.interact()
	_send(&"move_right")
	assert_eq(_focused().name, &"de")
	_send(&"interact")
	assert_eq(TranslationServer.get_locale(), "de")
	assert_eq(SettingsList.current_language(), "de")
	_send(&"move_back")
	assert_eq(_focused().name, &"ResetProgress")
	_send(&"move_back")
	assert_eq(_focused().name, &"ShowCredits")
	_send(&"move_right")
	assert_eq(_focused().name, &"Close")
	_send(&"interact")
	assert_null(_panel.user, "Close closes the menu")
	assert_null(_player.menu)
	assert_true(_terminal.enabled)


func test_pause_and_cancel_close_the_menu() -> void:
	for action: StringName in [&"pause", &"ui_cancel"]:
		_player.interact()
		_send(action)
		assert_null(_player.menu, action)


func test_pause_steps_back_from_the_credits() -> void:
	_player.interact()
	var menu := _panel.content as SettingsMenu
	var credits := menu.find_child("Credits", true, false) as Credits
	menu.show_credits(true)
	await wait_process_frames(1)
	assert_true(credits.visible)
	assert_eq(_focused().name, &"Back")
	_send(&"pause")
	assert_false(credits.visible, "back to the settings")
	assert_eq(_panel.user, _player, "still open")
	_send(&"pause")
	assert_null(_panel.user, "then it closes")


func test_mouse_clicks_through_the_screen() -> void:
	_player.interact()
	var button: Button = _panel.content.find_child("de", true, false) as Button
	var screen: Vector2 = _screen_position(button.get_global_rect().get_center())
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = screen
		get_viewport().push_input(click, true)
	assert_eq(TranslationServer.get_locale(), "de")


## The press that closed the menu doesn't act again in the world (here: reopen it).
func test_closing_press_does_not_act_again() -> void:
	_player.interact()
	Input.action_press(&"interact")
	_panel.close()
	await wait_physics_frames(3)
	assert_null(_panel.user)
	Input.action_release(&"interact")
	await wait_physics_frames(2)
	Input.action_press(&"interact")
	await wait_physics_frames(2)
	assert_eq(_panel.user, _player, "a new press uses the terminal again")


func test_camera_frames_the_screen() -> void:
	var rig: IsoCameraRig = _map.get_node("IsoCameraRig")
	_player.interact()
	await wait_seconds(1.5)
	assert_almost_eq(rig.zoom, _panel.view_height / rig.view_height(), 0.01)
	assert_lt(rig.global_position.distance_to(_panel.global_position), 0.05)
	_panel.close()
	await wait_seconds(1.5)
	assert_almost_eq(rig.zoom, 1.0, 0.01)


func test_rays_hit_the_front_of_the_screen() -> void:
	var front: Vector3 = _panel.global_basis.z
	var center: Vector3 = _panel.global_position
	var layout := Vector2(_panel.size * _panel.pixels_per_meter)
	assert_almost_eq(_panel.pixel_at(center + front, -front), layout * 0.5, Vector2.ONE * 0.5)
	var top_left: Vector3 = _panel.to_global(Vector3(-_panel.size.x, _panel.size.y, 0.0) * 0.45)
	var pixel: Vector2 = _panel.pixel_at(top_left + front, -front)
	assert_almost_eq(pixel, layout * 0.05, Vector2.ONE * 0.5)
	var beside: Vector3 = _panel.to_global(Vector3(_panel.size.x, 0.0, 0.0))
	assert_eq(_panel.pixel_at(beside + front, -front), Vector2.INF, "beside the screen")
	assert_eq(_panel.pixel_at(center - front, front), Vector2.INF, "from behind")


func test_languages_are_english_and_the_translations() -> void:
	assert_eq(SettingsList.languages(), PackedStringArray(["en", "de"]))
	for code: String in SettingsList.languages():
		assert_has(SettingsList.LANGUAGE_NAMES, code, "own name of " + code)


func _focused() -> Control:
	return _panel.content.get_viewport().gui_get_focus_owner()


## Presses and releases `action` as an input event.
func _send(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input(event)


## Where a menu pixel (layout size) shows on the screen.
func _screen_position(pixel: Vector2) -> Vector2:
	var uv: Vector2 = pixel / (_panel.size * _panel.pixels_per_meter)
	var at: Vector3 = _panel.to_global(
		Vector3((uv.x - 0.5) * _panel.size.x, (0.5 - uv.y) * _panel.size.y, 0.0)
	)
	return get_viewport().get_camera_3d().unproject_position(at)
