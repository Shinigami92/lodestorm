class_name PauseCard
extends Control
## The pause panel's card (in a `PausePanel` beside the player): its first page has "Resume",
## "Settings" and "Quit"; "Settings" shows the settings (`SettingsList`, the same as on the
## settings terminal) with a way to the credits, and "Quit" during a run asks first (the run is
## lost). `back` (also `pause`) steps back a page. Solo, its title says the game is paused; in
## co-op it says the game goes on. It keeps to the bottom of its screen and takes only the height
## its content needs.

enum Page { MAIN, SETTINGS, CREDITS, QUIT }

## The panel it's shown on.
var panel: PausePanel
## The page shown.
var page: Page = Page.MAIN

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


## Shows `shown_page`, its first button focused (while the panel is used).
func show_page(shown_page: Page) -> void:
	page = shown_page
	for each: Page in _pages:
		_pages[each].visible = each == page
	if page == Page.CREDITS:
		_credits.restart()
	_show_title()
	if panel and panel.user:
		var first: Control = _first.get(page, _pages[page].find_next_valid_focus())
		if first:
			first.grab_focus.call_deferred()


## Steps back a page: from the credits to the settings, from the others to the first page. Returns
## whether it did (false on the first page: the panel closes).
func back() -> bool:
	match page:
		Page.MAIN:
			return false
		Page.CREDITS:
			show_page(Page.SETTINGS)
		_:
			show_page(Page.MAIN)
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
