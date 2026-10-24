class_name SettingsMenu
extends PanelContainer
## The settings terminal's screen in cabin 1: the settings (`SettingsList`, the same as in the
## pause panel), the sound settings and the credits (pages of their own, `SoundList` and `Credits`;
## `back` or "Back" returns) and "Reset progress",
## which wipes the progress (`SaveGame.reset_progress`). Wiping can't be undone, so it asks three
## times, each time saying so; each confirm button only works after `confirm_delay`, so quick
## repeated presses can't get through, and cancel has the focus. Leaving the terminal drops the
## question. Resetting only works while the player is alone (`SaveGame.is_solo`): with others in
## the session the button is disabled with a hint, and everyone keeps their progress.

## Seconds before each confirm button of "Reset progress" can be pressed. TBD (playtest).
@export var confirm_delay: float = 1.0

## The confirmation step of "Reset progress": 0 not asked yet, 1 to 3 the questions.
var wipe_step: int = 0

var _confirm_left: float = 0.0

@onready var _settings: SettingsList = %Settings
@onready var _progress: Label = %Progress
@onready var _reset: Button = %ResetProgress
@onready var _reset_hint: Label = %ResetHint
@onready var _wipe: VBoxContainer = %Wipe
@onready var _wipe_warning: Label = %WipeWarning
@onready var _wipe_confirm: Button = %WipeConfirm
@onready var _wipe_cancel: Button = %WipeCancel
@onready var _close: Button = %Close
@onready var _credits: Credits = %Credits
@onready var _show_credits: Button = %ShowCredits
@onready var _sound: SoundList = %Sound
@onready var _show_sound: Button = %ShowSound
@onready var _back: Button = %Back


func _ready() -> void:
	_reset.pressed.connect(_on_reset_pressed)
	_wipe_confirm.pressed.connect(_on_wipe_confirm_pressed)
	_wipe_cancel.pressed.connect(cancel_wipe)
	_close.pressed.connect(_on_close_pressed)
	_show_credits.pressed.connect(show_credits.bind(true))
	_show_sound.pressed.connect(show_sound.bind(true))
	_back.pressed.connect(_on_back_pressed)
	show_credits(false)


func _process(delta: float) -> void:
	var solo: bool = SaveGame.is_solo(get_tree())
	_reset.disabled = not solo
	_reset_hint.visible = not solo and _reset.visible
	# Leaving the terminal (closing it any way) or someone joining drops the question.
	if wipe_step > 0:
		var panel: WorldPanel = WorldPanel.showing(self)
		if not solo or (panel and not panel.user):
			cancel_wipe()
	if _confirm_left > 0.0:
		_confirm_left = maxf(_confirm_left - delta, 0.0)
		_wipe_confirm.disabled = _confirm_left > 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_show_wipe_step()


## Stops asking about "Reset progress"; nothing is wiped.
func cancel_wipe() -> void:
	wipe_step = 0
	_show_wipe_step()


## The button that answers the current "Reset progress" question with yes.
func get_wipe_confirm_button() -> Button:
	return _wipe_confirm


func _on_reset_pressed() -> void:
	if not SaveGame.is_solo(get_tree()):
		return
	wipe_step = 1
	_show_wipe_step()


func _on_wipe_confirm_pressed() -> void:
	if wipe_step == 0 or _confirm_left > 0.0 or not SaveGame.is_solo(get_tree()):
		return
	if wipe_step < 3:
		wipe_step += 1
		_show_wipe_step()
		return
	wipe_step = 0
	var save_game := get_tree().get_first_node_in_group(SaveGame.GROUP) as SaveGame
	if save_game:
		save_game.reset_progress()
	_show_wipe_step()


## Shows the credits instead of the settings, or the settings again.
func show_credits(shown: bool) -> void:
	if shown:
		cancel_wipe()
		_credits.restart()
	_sound.visible = false
	_credits.visible = shown
	_show_page(_show_credits)


## Shows the sound settings instead of the settings, or the settings again.
func show_sound(shown: bool) -> void:
	if shown:
		cancel_wipe()
	_credits.visible = false
	_sound.visible = shown
	_show_page(_show_sound)


## Steps back from the sound settings or the credits (`pause` on the terminal). Returns whether it
## did.
func back() -> bool:
	if not _credits.visible and not _sound.visible:
		return false
	_on_back_pressed()
	return true


func _on_back_pressed() -> void:
	if _sound.visible:
		show_sound(false)
	else:
		show_credits(false)


## Shows "Back" on a page of its own and focuses the page's first control (the credits: "Back"),
## or focuses `opener` back on the settings.
func _show_page(opener: Button) -> void:
	var own_page: bool = _credits.visible or _sound.visible
	_back.visible = own_page
	_show_wipe_step()
	if not is_inside_tree() or not WorldPanel.showing(self):
		return
	var first: Control = opener
	if _sound.visible:
		first = _sound.find_next_valid_focus()
	elif own_page:
		first = _back
	first.grab_focus.call_deferred()


func _show_wipe_step() -> void:
	# While asking or showing a page of its own, only the question or that page shows.
	var settings_shown: bool = wipe_step == 0 and not _credits.visible and not _sound.visible
	_settings.visible = settings_shown
	_progress.visible = settings_shown
	_reset.visible = settings_shown
	_reset_hint.visible = settings_shown and not SaveGame.is_solo(get_tree())
	_show_credits.visible = settings_shown
	_show_sound.visible = settings_shown
	_wipe.visible = wipe_step > 0
	match wipe_step:
		1:
			_wipe_warning.text = tr(
				"This wipes all your progress: hold, weapons, upgrades. It can't be undone."
			)
			_wipe_confirm.text = tr("Reset progress (1/3)")
		2:
			_wipe_warning.text = tr(
				"Are you sure? Your progress will be gone for good, there is no way back."
			)
			_wipe_confirm.text = tr("Yes, reset it (2/3)")
		3:
			_wipe_warning.text = tr("Last chance: this wipes everything, irreversibly.")
			_wipe_confirm.text = tr("Reset everything (3/3)")
	if wipe_step > 0:
		_confirm_left = confirm_delay
		_wipe_confirm.disabled = true
		_wipe_cancel.grab_focus.call_deferred()


func _on_close_pressed() -> void:
	cancel_wipe()
	var panel: WorldPanel = WorldPanel.showing(self)
	if panel:
		panel.close()
