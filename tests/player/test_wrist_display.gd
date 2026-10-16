extends GutTest
## The wrist display: `wrist` shows a holo card beside the player with the cargo; the camera moves
## in while it's open.

const TEST_MAP := preload("res://tests/support/test_map.gd")
const CATALOG: OreCatalog = preload("res://game/ores/all_ores.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
## Body text is at least this share of the view's height (GAME_DESIGN.md, UI).
const MIN_TEXT_HEIGHT: float = 0.02

var _map: Node3D
var _player: Player


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	await wait_physics_frames(2)


func after_each() -> void:
	TranslationServer.set_locale("en")


func test_hidden_at_first() -> void:
	assert_false(_player.wrist.is_shown())
	assert_false(_panel().visible)


func test_wrist_toggles_it() -> void:
	await _press_wrist()
	assert_true(_player.wrist.is_shown())
	assert_true(_panel().visible)
	assert_eq(_player.menu, _player.wrist, "the player stands still meanwhile")
	await _press_wrist()
	assert_false(_player.wrist.is_shown())
	assert_null(_player.menu)


func test_shows_the_cargo_commonest_first() -> void:
	_player.add_cargo(VYREL, 30.0)
	_player.add_cargo(KYRITE, 12.5)
	_player.wrist.open(_player)
	var card: WristCard = _player.wrist.get_card()
	assert_eq(card.get_shown_ores(), [KYRITE, VYREL] as Array[OreType])
	_player.take_ore(KYRITE, 12.5)
	assert_eq(card.get_shown_ores(), [VYREL] as Array[OreType], "follows the cargo")


func test_floats_beside_the_player() -> void:
	_player.wrist.open(_player)
	await wait_process_frames(2)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var player_x: float = camera.unproject_position(_player.global_position).x
	var panel_x: float = camera.unproject_position(_panel().global_position).x
	assert_gt(panel_x, player_x, "to the camera's right of the player")
	assert_almost_eq(
		_panel().global_basis.z.normalized().dot(camera.global_basis.z),
		1.0,
		0.01,
		"faces the camera"
	)


func test_not_while_using_a_menu() -> void:
	_player.menu = _map.get_node("Ship/Rooms/Upper/Cabin1/BedStation") as WorldMenu
	await _press_wrist()
	assert_false(_player.wrist.is_shown())
	_player.menu = null


func test_every_ore_fits_in_every_language() -> void:
	for ore_type: OreType in CATALOG.ores:
		_player.add_cargo(ore_type, 123456.0)
	_player.wrist.open(_player)
	var card: WristCard = _player.wrist.get_card()
	var layout := Vector2(_panel().size * _panel().pixels_per_meter)
	for locale: String in SettingsMenu.languages():
		TranslationServer.set_locale(locale)
		card.show_cargo({})
		card.show_cargo(_player.cargo)
		var needed: Vector2 = card.get_needed_size()
		assert_lte(needed.x, layout.x + 0.5, "%s: %s wide" % [locale, needed.x])
		assert_lte(needed.y, layout.y + 0.5, "%s: %s high" % [locale, needed.y])


func test_text_is_big_enough() -> void:
	_player.wrist.open(_player)
	await wait_process_frames(2)
	var panel: WorldPanel = _panel()
	var text: float = WristCard.FONT_SIZE / panel.pixels_per_meter
	var text_height: float = text * panel.global_basis.y.length()
	assert_gte(text_height / _player.wrist.view_height, MIN_TEXT_HEIGHT)
	assert_gte(
		_player.wrist.view_height,
		panel.size.y + 0.5,
		"the view frames the card with room around it"
	)


func _panel() -> WorldPanel:
	return _player.wrist.get_node("Panel") as WorldPanel


func _press_wrist() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"wrist"
		event.pressed = pressed
		Input.parse_input_event(event)
		await wait_process_frames(2)
