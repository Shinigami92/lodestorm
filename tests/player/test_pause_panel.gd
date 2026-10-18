extends GutTest
## The pause panel: `pause` with no menu open shows a holo card beside the player (resume,
## settings, quit); solo the game stops meanwhile; the camera moves in while it's open.

const TEST_MAP := preload("res://tests/support/test_map.gd")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
## Body text is at least this share of the view's height (GAME_DESIGN.md, UI).
const MIN_TEXT_HEIGHT: float = 0.02

var _map: Node3D
var _player: Player
var _panel: PausePanel


func before_each() -> void:
	# GUT waits on while the game is paused; the map stops.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_map = TEST_MAP.instantiate() as Node3D
	_map.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_panel = _player.pause_panel
	_panel.quits = false
	await wait_physics_frames(2)


func after_each() -> void:
	TranslationServer.set_locale("en")
	PausePanel.pause_on_focus_loss = false
	get_tree().paused = false
	process_mode = Node.PROCESS_MODE_INHERIT


func test_hidden_at_first() -> void:
	assert_false(_panel.is_shown())
	assert_false(_panel.visible)
	assert_false(get_tree().paused)


func test_pause_toggles_it_and_stops_the_game() -> void:
	await _press(&"pause")
	assert_true(_panel.is_shown())
	assert_true(_panel.visible)
	assert_eq(_player.menu, _panel, "the player stands still meanwhile")
	assert_true(get_tree().paused, "solo, the game stops")
	assert_eq(_panel.get_card().page, PauseCard.Page.MAIN)
	await _press(&"pause")
	assert_false(_panel.is_shown())
	assert_null(_player.menu)
	assert_false(get_tree().paused, "and goes on")


func test_resume_closes_it() -> void:
	_panel.open(_player)
	(_panel.get_card().find_child("Resume", true, false) as Button).pressed.emit()
	assert_false(_panel.is_shown())
	assert_false(get_tree().paused)


func test_pause_steps_back_through_the_pages() -> void:
	_panel.open(_player)
	var card: PauseCard = _panel.get_card()
	(card.find_child("Settings", true, false) as Button).pressed.emit()
	assert_eq(card.page, PauseCard.Page.SETTINGS)
	assert_not_null(card.find_child("Languages", true, false), "the same settings as the terminal")
	(card.find_child("ShowCredits", true, false) as Button).pressed.emit()
	assert_eq(card.page, PauseCard.Page.CREDITS)
	await _press(&"pause")
	assert_eq(card.page, PauseCard.Page.SETTINGS)
	await _press(&"pause")
	assert_eq(card.page, PauseCard.Page.MAIN)
	assert_true(_panel.is_shown())
	await _press(&"pause")
	assert_false(_panel.is_shown())


func test_stepping_back_focuses_the_button_that_opened_the_page() -> void:
	_panel.open(_player)
	var card: PauseCard = _panel.get_card()
	(card.find_child("Settings", true, false) as Button).pressed.emit()
	(card.find_child("SettingsBack", true, false) as Button).pressed.emit()
	await wait_process_frames(2)
	var focused: Control = card.get_viewport().gui_get_focus_owner()
	assert_eq(focused, card.find_child("Settings", true, false), "not Quit")


func test_a_click_after_a_page_change_waits_for_the_pointer_to_move() -> void:
	_panel.open(_player)
	var card: PauseCard = _panel.get_card()
	await wait_process_frames(2)
	var settings := card.find_child("Settings", true, false) as Button
	var at: Vector2 = settings.get_global_rect().get_center()
	_mouse(card, at)
	_click(card, at)
	await wait_process_frames(1)
	assert_eq(card.page, PauseCard.Page.MAIN, "the pointer hasn't moved since the page showed")
	_mouse(card, at + Vector2(PauseCard.CLICK_GUARD * 2.0, 0.0))
	_mouse(card, at)
	_click(card, at)
	await wait_process_frames(1)
	assert_eq(card.page, PauseCard.Page.SETTINGS, "it moved: the click counts")


func test_the_camera_frames_it_while_paused() -> void:
	var rig: IsoCameraRig = _map.get_node("IsoCameraRig")
	_panel.open(_player)
	await wait_seconds(1.5)
	assert_true(get_tree().paused)
	assert_almost_eq(rig.zoom, _panel.view_height / rig.view_height(), 0.01)
	assert_lt(rig.global_position.distance_to(_panel.get_view_center()), 0.05)


func test_the_game_stops_while_paused() -> void:
	var ship: Ship = _map.get_node("Ship")
	ship.ramp_duration = 0.25
	TEST_MAP.pick_mission(_map)
	ship.ramp_button.use(_player)
	_panel.open(_player)
	await wait_seconds(0.5)
	assert_false(ship.is_ramp_down(), "the ramp stands still")
	_panel.close()
	await wait_seconds(0.5)
	assert_true(ship.is_ramp_down(), "and goes on")


func test_co_op_goes_on() -> void:
	var guest := PLAYER_SCENE.instantiate() as Player
	_map.add_child(guest)
	await wait_physics_frames(1)
	_panel.open(_player)
	assert_false(get_tree().paused, "others are playing")
	assert_false(_panel.pausing)
	var note := _panel.get_card().find_child("Note", true, false) as Label
	assert_true(note.visible, "says so")
	_panel.close()
	guest.free()


func test_someone_joining_lets_the_game_go_on() -> void:
	_panel.open(_player)
	assert_true(get_tree().paused)
	var guest := PLAYER_SCENE.instantiate() as Player
	_map.add_child(guest)
	await wait_process_frames(2)
	assert_false(get_tree().paused)
	_panel.close()
	guest.free()


func test_focus_loss_pauses_solo() -> void:
	_panel.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(_panel.is_shown(), "not while turned off")
	PausePanel.pause_on_focus_loss = true
	_panel.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_true(_panel.is_shown())
	assert_true(get_tree().paused)
	_panel.close()


func test_not_while_using_a_menu() -> void:
	_player.menu = _map.get_node("Ship/Rooms/Upper/Cabin1/BedStation") as WorldMenu
	await _press(&"pause")
	assert_false(_panel.is_shown())
	_player.menu = null


func test_quit_aboard_quits_at_once() -> void:
	_panel.open(_player)
	assert_false(_panel.loses_run())
	assert_true(_panel.quit(), "no question aboard")
	assert_true(_panel.quitting)
	assert_false(_panel.quit(), "once is enough")


func test_quit_during_a_run_asks_first() -> void:
	TEST_MAP.pick_mission(_map)
	(_map.get_node("Ship") as Ship).ramp_button.use(_player)
	await wait_physics_frames(2)
	_panel.open(_player)
	assert_true(_panel.loses_run())
	assert_false(_panel.quit(), "asks first")
	assert_eq(_panel.get_card().page, PauseCard.Page.QUIT)
	assert_false(_panel.quitting)
	(_panel.get_card().find_child("QuitConfirm", true, false) as Button).pressed.emit()
	assert_true(_panel.quitting, "the run is lost")


func test_floats_beside_the_player() -> void:
	_panel.open(_player)
	await wait_process_frames(2)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var player_x: float = camera.unproject_position(_player.global_position).x
	var panel_x: float = camera.unproject_position(_panel.global_position).x
	assert_gt(panel_x, player_x, "to the camera's right of the player")
	assert_almost_eq(
		_panel.global_basis.z.normalized().dot(camera.global_basis.z), 1.0, 0.01, "faces the camera"
	)


func test_every_page_fits_in_every_language() -> void:
	_panel.open(_player)
	var card: PauseCard = _panel.get_card()
	var layout := Vector2(_panel.size * _panel.pixels_per_meter)
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		for page: PauseCard.Page in PauseCard.Page.values():
			card.show_page(page)
			await wait_process_frames(1)
			var needed: Vector2 = card.get_needed_size()
			assert_lte(needed.x, layout.x + 0.5, "%s %s: %s wide" % [locale, page, needed.x])
			assert_lte(needed.y, layout.y + 0.5, "%s %s: %s high" % [locale, page, needed.y])
	_panel.close()


func test_text_is_big_enough() -> void:
	var theme: Theme = load("res://assets/ui/terminal_theme.tres")
	var text: float = Credits.SMALL_FONT_SIZE / _panel.pixels_per_meter
	assert_lte(Credits.SMALL_FONT_SIZE, theme.default_font_size, "the smallest text")
	assert_gte(text / _panel.view_height, MIN_TEXT_HEIGHT)
	assert_gte(
		_panel.view_height, _panel.size.y + 0.5, "the view frames the card with room around it"
	)


func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await wait_process_frames(2)


func _mouse(card: PauseCard, at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	card.get_viewport().push_input(motion, true)


func _click(card: PauseCard, at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		card.get_viewport().push_input(click, true)
