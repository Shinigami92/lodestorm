class_name SettingsList
extends VBoxContainer
## The player's settings, the same wherever they're changed (the pause panel and the settings
## terminal in cabin 1, see GAME_DESIGN.md, UI): so far the language, picking one switches the
## game's texts right away and saves it (see `GameSettings`). The sound volumes and the suit ring's
## options join it with their features.

## Each language's name, written in that language.
const LANGUAGE_NAMES: Dictionary[String, String] = {"en": "English", "de": "Deutsch"}

@onready var _languages: HBoxContainer = %Languages


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
