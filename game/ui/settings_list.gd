class_name SettingsList
extends GridContainer
## The player's settings, the same wherever they're changed (the pause panel and the settings
## terminal in cabin 1, see GAME_DESIGN.md, UI): the language (picking one switches the game's
## texts right away), the suit ring's size and "Always show", and a volume per sound bus (a slider
## in 10 % steps; changing it plays a sample on that bus), each saved at once
## (see `GameSettings`).

## Each language's name, written in that language.
const LANGUAGE_NAMES: Dictionary[String, String] = {"en": "English", "de": "Deutsch"}
## What a volume slider plays when it changes: a shot on the Master and Effects buses, the storm
## on the Ambience bus (once at a time).
const SHOT: Sound = preload("res://assets/audio/sfx/weapons/blaster_shot.tres")
const SAMPLES: Dictionary[StringName, Sound] = {
	&"Master": SHOT,
	&"Effects": SHOT,
	&"Ambience": preload("res://assets/audio/sfx/mission/storm.tres"),
}

@onready var _languages: HBoxContainer = %Languages
@onready var _ring_sizes: HBoxContainer = %RingSizes
@onready var _always_show: CheckBox = %AlwaysShow


func _ready() -> void:
	var group := ButtonGroup.new()
	var current: String = current_language()
	for code: String in languages():
		var button := Button.new()
		button.name = code
		button.text = LANGUAGE_NAMES.get(code, TranslationServer.get_locale_name(code))
		# The names stay in their own language.
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = code == current
		button.pressed.connect(GameSettings.set_language.bind(code))
		_languages.add_child(button)
	var sizes := ButtonGroup.new()
	for index: int in _ring_sizes.get_child_count():
		var button := _ring_sizes.get_child(index) as Button
		button.button_group = sizes
		button.button_pressed = index == GameSettings.ring_size
		button.pressed.connect(GameSettings.set_ring_size.bind(index))
	_always_show.button_pressed = GameSettings.ring_always_show
	_always_show.toggled.connect(GameSettings.set_ring_always_show)
	var ring_row: Array[Control] = []
	ring_row.assign(_ring_sizes.get_children())
	ring_row.append(_always_show)
	for bus: StringName in Sfx.BUSES:
		var row := get_node("%" + bus) as HBoxContainer
		var slider := row.get_node(^"Slider") as HSlider
		slider.value = GameSettings.volume(bus)
		_show_volume(row, slider.value)
		slider.value_changed.connect(_on_volume_changed.bind(bus, row))
	var language_row: Array[Control] = []
	language_row.assign(_languages.get_children())
	_chain(language_row)
	_chain(ring_row)


func _on_volume_changed(level: float, bus: StringName, row: HBoxContainer) -> void:
	GameSettings.set_volume(bus, level)
	_show_volume(row, level)
	if bus in SAMPLES:
		Sfx.play_ui(SAMPLES[bus], bus)


static func _show_volume(row: HBoxContainer, level: float) -> void:
	(row.get_node(^"Value") as Label).text = "%d %%" % roundi(level * 100.0)


## Makes left and right step along `row` (else a button in the row below may be nearer).
static func _chain(row: Array[Control]) -> void:
	for index: int in range(1, row.size()):
		row[index - 1].focus_neighbor_right = row[index].get_path()
		row[index].focus_neighbor_left = row[index - 1].get_path()


## The game's languages: English (the texts' originals) and every translation in the project
## settings.
static func languages() -> PackedStringArray:
	var codes := PackedStringArray(["en"])
	var paths: PackedStringArray = ProjectSettings.get_setting(
		"internationalization/locale/translations"
	)
	for path: String in paths:
		var code: String = (load(path) as Translation).locale
		if code not in codes:
			codes.append(code)
	return codes


## The language the game shows right now (English for languages it doesn't have).
static func current_language() -> String:
	var code: String = TranslationServer.get_locale().get_slice("_", 0)
	return code if code in languages() else "en"
