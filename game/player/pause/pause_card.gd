class_name PauseCard
extends Control
## The pause panel's card (in a `PausePanel` beside the player): its first page has "Resume",
## "Settings" and "Quit"; "Settings" shows the settings (`SettingsList`, the same as on the
## settings terminal) with a way to the credits, and "Quit" during a run asks first (the run is
## lost). `back` (also `pause`) steps back a page. Solo, its title says the game is paused; in
## co-op it says the game goes on. It keeps to the bottom of its screen and takes only the height
## its content needs, so a page's last button (e.g. "Back") sits where the next page's last one
## ("Quit") appears: after a page change, mouse clicks only count once the pointer moved
## `CLICK_GUARD` pixels, and stepping back focuses the button that opened the page.

enum Page { MAIN, SETTINGS, CREDITS, QUIT }

## Pixels the pointer has to move after a page change before a click counts.
const CLICK_GUARD: float = 12.0

## The panel it's shown on.
var panel: PausePanel
## The page shown.
var page: Page = Page.MAIN

## Whether mouse clicks wait for the pointer to move, and where it was first seen meanwhile.
var _click_guard: bool = false
var _guard_from := Vector2.INF

@onready var _panel: Control = %Panel
@onready var _title: Label = %Title
@onready var _note: Label = %Note
@onready var _pages: Dictionary[Page, Control] = {
	Page.MAIN: %Main,
	Page.SETTINGS: %SettingsPage,
	Page.CREDITS: %CreditsPage,
	Page.QUIT: %QuitPage,
}
## The control a page focuses first, where it isn't its first one (asked to quit: "Cancel").
@onready var _first: Dictionary[Page, Control] = {Page.QUIT: %QuitCancel}
## The button that opens each page from the one before it (focused when stepping back to that).
@onready var _opener: Dictionary[Page, Control] = {
	Page.SETTINGS: %Settings, Page.CREDITS: %ShowCredits, Page.QUIT: %Quit
}
@onready var _credits: Credits = %Credits


func _ready() -> void:
	(%Resume as Button).pressed.connect(_on_resume_pressed)
	(%Settings as Button).pressed.connect(show_page.bind(Page.SETTINGS))
	(%Quit as Button).pressed.connect(_on_quit_pressed)
	(%ShowCredits as Button).pressed.connect(show_page.bind(Page.CREDITS))
	(%SettingsBack as Button).pressed.connect(back)
	(%CreditsBack as Button).pressed.connect(back)
	(%QuitConfirm as Button).pressed.connect(_on_quit_confirmed)
	(%QuitCancel as Button).pressed.connect(back)
	show_page(Page.MAIN)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_show_title()


func _input(event: InputEvent) -> void:
	if not _click_guard:
		return
	var motion := event as InputEventMouseMotion
	var button := event as InputEventMouseButton
	if motion:
		if not _guard_from.is_finite():
			_guard_from = motion.position
		elif motion.position.distance_to(_guard_from) > CLICK_GUARD:
			_click_guard = false
	elif button and button.pressed:
		get_viewport().set_input_as_handled()


## Shows `shown_page`, its first button focused (while the panel is used), or `focus` instead.
## Mouse clicks wait until the pointer moves.
func show_page(shown_page: Page, focus: Control = null) -> void:
	page = shown_page
	_click_guard = true
	_guard_from = Vector2.INF
	for each: Page in _pages:
		_pages[each].visible = each == page
	if page == Page.CREDITS:
		_credits.restart()
	_show_title()
	if panel and panel.user:
		var first: Control = (
			focus if focus else _first.get(page, _pages[page].find_next_valid_focus())
		)
		if first:
			first.grab_focus.call_deferred()


## Steps back a page: from the credits to the settings, from the others to the first page. Returns
## whether it did (false on the first page: the panel closes).
func back() -> bool:
	var from: Page = page
	match page:
		Page.MAIN:
			return false
		Page.CREDITS:
			show_page(Page.SETTINGS, _opener[from])
		_:
			show_page(Page.MAIN, _opener[from])
	return true


## The size its content needs (for the fit test).
func get_needed_size() -> Vector2:
	return _panel.get_combined_minimum_size()


func _show_title() -> void:
	var paused: bool = panel != null and panel.pausing
	match page:
		Page.MAIN:
			_title.text = tr("Paused") if paused else tr("Menu")
		Page.SETTINGS:
			_title.text = tr("Settings")
		Page.CREDITS:
			_title.text = tr("Credits")
		Page.QUIT:
			_title.text = tr("Quit the game?")
	_note.visible = page == Page.MAIN and not paused
	_note.text = tr("The game goes on.")


func _on_resume_pressed() -> void:
	if panel:
		panel.close()


func _on_quit_pressed() -> void:
	if panel:
		panel.quit()


func _on_quit_confirmed() -> void:
	if panel:
		panel.quit(true)
