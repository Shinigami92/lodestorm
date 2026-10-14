class_name SettingsMenu
extends PanelContainer
## The game's settings, shown on a terminal's screen: the language (picking one switches the
## game's texts right away and saves it, see `GameSettings`) and "New game", which wipes the
## progress (`SaveGame.new_game`). Wiping can't be undone, so it asks three times, each time
## saying so; each confirm button only works after `confirm_delay`, so quick repeated presses
## can't get through, and cancel has the focus. Leaving the terminal drops the question.

## Each language's name, written in that language.
const LANGUAGE_NAMES: Dictionary[String, String] = {"en": "English", "de": "Deutsch"}

## Seconds before each confirm button of "New game" can be pressed. TBD (playtest).
@export var confirm_delay: float = 1.0

## The confirmation step of "New game": 0 not asked yet, 1 to 3 the questions.
var wipe_step: int = 0

var _confirm_left: float = 0.0

@onready var _language_label: Label = %Language
@onready var _languages: HBoxContainer = %Languages
@onready var _new_game: Button = %NewGame
@onready var _wipe: VBoxContainer = %Wipe
@onready var _wipe_warning: Label = %WipeWarning
@onready var _wipe_confirm: Button = %WipeConfirm
@onready var _wipe_cancel: Button = %WipeCancel
@onready var _close: Button = %Close


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
	_new_game.pressed.connect(_on_new_game_pressed)
	_wipe_confirm.pressed.connect(_on_wipe_confirm_pressed)
	_wipe_cancel.pressed.connect(cancel_wipe)
	_close.pressed.connect(_on_close_pressed)
	_show_wipe_step()


func _process(delta: float) -> void:
	# Leaving the terminal (closing it any way) drops the question.
	if wipe_step > 0:
		var panel: WorldPanel = WorldPanel.showing(self)
		if panel and not panel.user:
			cancel_wipe()
	if _confirm_left > 0.0:
		_confirm_left = maxf(_confirm_left - delta, 0.0)
		_wipe_confirm.disabled = _confirm_left > 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_show_wipe_step()


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


## Stops asking about "New game"; nothing is wiped.
func cancel_wipe() -> void:
	wipe_step = 0
	_show_wipe_step()


## The button that answers the current "New game" question with yes.
func get_wipe_confirm_button() -> Button:
	return _wipe_confirm


func _on_new_game_pressed() -> void:
	wipe_step = 1
	_show_wipe_step()


func _on_wipe_confirm_pressed() -> void:
	if wipe_step == 0 or _confirm_left > 0.0:
		return
	if wipe_step < 3:
		wipe_step += 1
		_show_wipe_step()
		return
	wipe_step = 0
	var save_game := get_tree().get_first_node_in_group(SaveGame.GROUP) as SaveGame
	if save_game:
		save_game.new_game()
	_show_wipe_step()


func _show_wipe_step() -> void:
	# While asking, only the question shows.
	_languages.visible = wipe_step == 0
	_language_label.visible = wipe_step == 0
	_new_game.visible = wipe_step == 0
	_wipe.visible = wipe_step > 0
	match wipe_step:
		1:
			_wipe_warning.text = tr(
				"This wipes all your progress: hold, weapons, upgrades. It can't be undone."
			)
			_wipe_confirm.text = tr("Wipe progress (1/3)")
		2:
			_wipe_warning.text = tr(
				"Are you sure? Your progress will be gone for good, there is no way back."
			)
			_wipe_confirm.text = tr("Yes, wipe it (2/3)")
		3:
			_wipe_warning.text = tr("Last chance: this wipes everything, irreversibly.")
			_wipe_confirm.text = tr("Wipe everything (3/3)")
	if wipe_step > 0:
		_confirm_left = confirm_delay
		_wipe_confirm.disabled = true
		_wipe_cancel.grab_focus.call_deferred()


func _on_close_pressed() -> void:
	cancel_wipe()
	var panel: WorldPanel = WorldPanel.showing(self)
	if panel:
		panel.close()
