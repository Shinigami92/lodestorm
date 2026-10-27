extends GutTest
## The title view: the game opens on the ship from outside with the name; any button glides into
## the ship; the credits show after a while without input.

const MAP: PackedScene = preload("res://game/maps/main.tscn")
## Body text is at least this share of the view's height (docs/design/ui.md).
const MIN_TEXT_HEIGHT: float = 0.02

var _map: Node3D
var _title: TitleView
var _player: Player
var _ship: Ship


func before_each() -> void:
	TitleView.shows = true
	_map = MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_title = _map.get_node("TitleView") as TitleView
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	await wait_process_frames(3)


func after_each() -> void:
	TitleView.shows = false
	TranslationServer.set_locale("en")


func test_opens_on_the_title() -> void:
	assert_eq(_title.user, _player, "the first player stands still meanwhile")
	assert_eq(_player.menu, _title)
	assert_true(_ship.show_outside, "the ship from outside")
	assert_true(_ship.countdown_hidden)
	assert_false(_player.silhouette_shown, "not through the roof")
	assert_false(_navigator_view().is_visible_in_tree(), "its name plates neither")
	var rig: IsoCameraRig = _map.get_node("IsoCameraRig")
	assert_almost_eq(rig.zoom, _title.view_height / rig.view_height(), 0.01, "right away")


func test_any_button_starts() -> void:
	await _press_key(KEY_SPACE)
	assert_null(_title.user)
	assert_null(_player.menu)
	assert_false(_ship.show_outside, "into the ship")
	assert_false(_ship.countdown_hidden)
	assert_true(_player.silhouette_shown)
	assert_false(_player.pause_panel.is_shown(), "the press doesn't do more")


func test_moving_the_mouse_is_no_button() -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(30.0, 0.0)
	assert_false(TitleView.is_button(motion))
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	assert_true(TitleView.is_button(key))
	key.echo = true
	assert_false(TitleView.is_button(key), "a held key's repeats")
	var pad := InputEventJoypadButton.new()
	pad.pressed = true
	assert_true(TitleView.is_button(pad))


func test_credits_after_a_while() -> void:
	_title.credits_delay = 0.2
	await wait_seconds(0.4)
	assert_true(_title.credits_shown())
	await _press_key(KEY_SPACE)
	assert_false(_title.credits_shown(), "back to the prompt")
	assert_eq(_title.user, _player, "not started yet")
	await _press_key(KEY_SPACE)
	assert_null(_title.user)


func test_credits_text_reads() -> void:
	var panel: WorldPanel = _title.get_node("Credits") as WorldPanel
	var text: float = Credits.SMALL_FONT_SIZE / panel.pixels_per_meter
	assert_gte(text / _title.view_height, MIN_TEXT_HEIGHT, "even the license texts")
	var layout := Vector2(panel.size * panel.pixels_per_meter)
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		await wait_process_frames(1)
		var needed: Vector2 = panel.content.get_combined_minimum_size()
		assert_lte(needed.x, layout.x + 0.5, "%s: %s wide" % [locale, needed.x])
		assert_lte(needed.y, layout.y + 0.5, "%s: %s high" % [locale, needed.y])


func _navigator_view() -> Node3D:
	return _ship.get_node("Rooms/Upper/Bridge/Navigator/View") as Node3D


func _press_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await wait_process_frames(2)
