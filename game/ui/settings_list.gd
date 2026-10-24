class_name SettingsList
extends GridContainer
## The player's settings, the same wherever they're changed (the pause panel and the settings
## terminal in cabin 1, see GAME_DESIGN.md, UI): the language (picking one switches the game's
## texts right away), the language the NPCs speak (or "Off"; until one is picked it follows the
## texts, see `VoiceLines`; picking one plays a sample), whether talks continue by themselves
## ("Dialogue", see `Npc`), the suit ring's size and "Always show",
## each saved at once (see `GameSettings`), and "Open folder", which shows the game's log files in
## the system's file manager (for bug reports). The volumes are a page of their own (`SoundList`).

## Each language's name, written in that language.
const LANGUAGE_NAMES: Dictionary[String, String] = {"en": "English", "de": "Deutsch"}
## Plays the voice sample (one at a time: the next one replaces it).
var _voice_sample: AudioStreamPlayer

@onready var _languages: HBoxContainer = %Languages
@onready var _voice_languages: HBoxContainer = %VoiceLanguages
@onready var _auto_continue: CheckBox = %AutoContinue
@onready var _ring_sizes: HBoxContainer = %RingSizes
@onready var _always_show: CheckBox = %AlwaysShow
@onready var _open_logs: Button = %OpenLogs


func _ready() -> void:
	_voice_sample = VoiceLines.sample_player(self)
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
		button.pressed.connect(_on_language_pressed.bind(code))
		_languages.add_child(button)
	# The voice languages go in front of "Off" (in the scene, so its text is translated).
	var voices := ButtonGroup.new()
	var off := _voice_languages.get_node(VoiceLines.OFF) as Button
	for code: String in VoiceLines.LANGUAGES:
		var button := Button.new()
		button.name = code
		button.text = LANGUAGE_NAMES.get(code, TranslationServer.get_locale_name(code))
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.toggle_mode = true
		_voice_languages.add_child(button)
		_voice_languages.move_child(button, off.get_index())
	for button: Button in _voice_languages.get_children():
		button.button_group = voices
		button.pressed.connect(_on_voice_language_pressed.bind(String(button.name)))
	_show_voice_language()
	var sizes := ButtonGroup.new()
	for index: int in _ring_sizes.get_child_count():
		var button := _ring_sizes.get_child(index) as Button
		button.button_group = sizes
		button.button_pressed = index == GameSettings.ring_size
		button.pressed.connect(GameSettings.set_ring_size.bind(index))
	_auto_continue.button_pressed = GameSettings.dialogue_auto_continue
	_auto_continue.toggled.connect(GameSettings.set_dialogue_auto_continue)
	_always_show.button_pressed = GameSettings.ring_always_show
	_always_show.toggled.connect(GameSettings.set_ring_always_show)
	var ring_row: Array[Control] = []
	ring_row.assign(_ring_sizes.get_children())
	ring_row.append(_always_show)
	var language_row: Array[Control] = []
	language_row.assign(_languages.get_children())
	_chain(language_row)
	var voice_row: Array[Control] = []
	voice_row.assign(_voice_languages.get_children())
	_chain(voice_row)
	_chain(ring_row)
	_open_logs.pressed.connect(_on_open_logs_pressed)


func _on_language_pressed(code: String) -> void:
	GameSettings.set_language(code)
	# Voices that follow the texts follow them now.
	_show_voice_language()


func _on_voice_language_pressed(code: String) -> void:
	GameSettings.set_voice_language(code)
	VoiceLines.play_sample(_voice_sample)


## Lights the voice language spoken now (or "Off").
func _show_voice_language() -> void:
	var spoken: String = VoiceLines.spoken_language()
	var shown: String = spoken if spoken else VoiceLines.OFF
	for button: Button in _voice_languages.get_children():
		button.set_pressed_no_signal(button.name == shown)


func _on_open_logs_pressed() -> void:
	OS.shell_show_in_file_manager(logs_folder())


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


## The folder of the game's log files (Godot's file logging, `debug/file_logging/log_path`), as a
## path of the system.
static func logs_folder() -> String:
	var log_path: String = ProjectSettings.get_setting("debug/file_logging/log_path")
	return ProjectSettings.globalize_path(log_path.get_base_dir())
