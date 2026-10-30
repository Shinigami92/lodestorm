class_name TalkCard
extends StationCard
## The holo card beside an NPC while a player talks to them (`Npc`): their name and role, then
## either the open topics and "Goodbye" (an amber dot on topics nobody has heard yet), or while a
## topic is told its title, how far it is ("2 / 3") and "Continue" ("Done" on the last line) and
## "Back". The button `interact` presses has an amber frame (not the focus, see `LoadoutCard`).
## Past `MAX_ROWS` entries the list scrolls, keeping the framed one in view (an NPC with many
## topics, like the bartender's rumors about every planet). With auto-continue on, an amber bar
## along the bottom of "Continue" fills until the line moves on by itself (`show_progress`), and a
## square button right of it pauses that (a pause icon) or resumes it (a play icon).

## Button states framed amber on the selected button.
const SELECTED_STATES: Array[StringName] = [
	&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"
]
## Marks a topic nobody has heard yet.
const NEW_DOT: String = "●  "
## The most entries the list shows at once; more scroll.
const MAX_ROWS: int = 7
## Height of the auto-continue bar and its inset from the button's edges (inside the amber
## frame), in px.
const PROGRESS_HEIGHT: float = 7.0
const PROGRESS_INSET: float = 7.0
const PAUSE_ICON: Texture2D = preload("res://assets/ui/pause.svg")
const PLAY_ICON: Texture2D = preload("res://assets/ui/play.svg")
## The button states whose icon takes the text's color.
const ICON_COLORS: Dictionary[StringName, StringName] = {
	&"icon_normal_color": &"font_color",
	&"icon_hover_color": &"font_hover_color",
	&"icon_pressed_color": &"font_pressed_color",
	&"icon_hover_pressed_color": &"font_hover_pressed_color",
	&"icon_focus_color": &"font_focus_color",
}

var _buttons: Array[Button] = []
## The amber-framed styles of the selected button, per state.
var _selected_styles: Dictionary[StringName, StyleBox] = {}
## The auto-continue bar along the bottom of the first button (made when first shown).
var _progress_bar: ColorRect
## Pauses or resumes moving on by itself: right of the first button (made with it).
var _pause_button: Button

@onready var _name: Label = %Name
@onready var _role: Label = %Role
@onready var _topic_title: Label = %TopicTitle
@onready var _progress: Label = %Progress
@onready var _scroll: ScrollContainer = %Scroll
@onready var _list: VBoxContainer = %List


func show_part(part: StationPart) -> void:
	var npc := station as Npc
	visible = part != null and npc != null and npc.profile != null
	if not visible:
		return
	_name.text = npc.profile.display_name
	_role.text = tr(npc.profile.role)
	_role.add_theme_color_override(&"font_color", CardPalette.HINT)
	var told: Topic = npc.talk.topic
	_topic_title.visible = told != null
	_progress.visible = told != null
	if told:
		_topic_title.text = tr(told.title)
		var lines: int = npc.talk.get_topic_lines().size()
		_progress.text = "%d / %d" % [npc.talk.line + 1, lines]
		var last: bool = npc.talk.line + 1 >= lines
		_show_buttons([tr("Done") if last else tr("Continue"), tr("Back")], [false, false], 0)
		_pause_button.visible = npc.talk.get_auto_progress() >= 0.0
		_pause_button.icon = PLAY_ICON if npc.talk.auto_paused else PAUSE_ICON
		return
	var texts: Array[String] = []
	var new: Array[bool] = []
	for choice: Topic in npc.get_choices():
		texts.append(tr(choice.title))
		new.append(npc.is_new(choice))
	texts.append(tr("Goodbye"))
	new.append(false)
	_show_buttons(texts, new, npc.talk.choice)
	_pause_button.visible = false


## Shows how far the line is towards moving on by itself (0..1) as the bar on "Continue"; hides it
## when below 0.
func show_progress(fraction: float) -> void:
	var shown: bool = fraction >= 0.0 and not _buttons.is_empty()
	if _progress_bar:
		_progress_bar.visible = shown
	if not shown:
		return
	var button: Button = _buttons[0]
	if not _progress_bar:
		_progress_bar = ColorRect.new()
		_progress_bar.name = "AutoContinue"
		_progress_bar.color = CardPalette.STATUS
		_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(_progress_bar)
	_progress_bar.position = Vector2(
		PROGRESS_INSET, button.size.y - PROGRESS_INSET - PROGRESS_HEIGHT
	)
	_progress_bar.size = Vector2((button.size.x - PROGRESS_INSET * 2.0) * fraction, PROGRESS_HEIGHT)


## The auto-continue bar (for tests and probes), or null before it first showed.
func get_progress_bar() -> ColorRect:
	return _progress_bar


func press_primary() -> bool:
	var npc := station as Npc
	if not npc:
		return false
	npc.talk.press()
	return true


## The button that pauses or resumes moving on by itself (for tests and probes), or null before the
## card first showed.
func get_pause_button() -> Button:
	return _pause_button


## The button showing `text` (for tests and probes), or null.
func get_button(text: String) -> Button:
	for button: Button in _buttons:
		if button.visible and button.text.trim_prefix(NEW_DOT) == text:
			return button
	return null


## One button per entry in `texts` (`new`: with the amber dot), `selected` framed amber.
func _show_buttons(texts: Array[String], new: Array[bool], selected: int) -> void:
	while _buttons.size() < texts.size():
		var button := Button.new()
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_button_pressed.bind(_buttons.size()))
		if _buttons.is_empty():
			_list.add_child(_first_row(button))
		else:
			_list.add_child(button)
		_buttons.append(button)
	for i: int in _buttons.size():
		var button: Button = _buttons[i]
		button.visible = i < texts.size()
		if not button.visible:
			continue
		button.text = (NEW_DOT if new[i] else "") + texts[i]
		if new[i]:
			button.add_theme_color_override(&"font_color", CardPalette.STATUS)
		else:
			button.remove_theme_color_override(&"font_color")
		for state: StringName in SELECTED_STATES:
			if i == selected:
				button.add_theme_stylebox_override(state, _selected_style(button, state))
			else:
				button.remove_theme_stylebox_override(state)
	var gap: int = _list.get_theme_constant(&"separation")
	var row: float = _buttons[0].get_combined_minimum_size().y + gap
	_scroll.custom_minimum_size.y = mini(texts.size(), MAX_ROWS) * row - gap
	_scroll_to.call_deferred(selected)


## A row with `button` (the first one, "Continue" while a topic is told) and the pause button right
## of it, square, hidden while it doesn't apply.
func _first_row(button: Button) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "FirstRow"
	row.add_theme_constant_override(&"separation", _list.get_theme_constant(&"separation"))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)
	_pause_button = Button.new()
	_pause_button.name = "Pause"
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.icon = PAUSE_ICON
	_pause_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_button.visible = false
	_pause_button.pressed.connect(_on_pause_pressed)
	row.add_child(_pause_button)
	_fit_pause_button.call_deferred(button)
	return row


## Makes the pause button as wide as it's tall (the first button's height: its sides' margins
## leave just the icon between them), its icon in the text's colors (once in the card's theme).
func _fit_pause_button(button: Button) -> void:
	var side: float = button.get_combined_minimum_size().y
	var margin: float = maxf((side - PAUSE_ICON.get_width()) * 0.5, 0.0)
	for state: StringName in SELECTED_STATES + [&"focus"]:
		var style: StyleBox = _pause_button.get_theme_stylebox(state).duplicate()
		style.content_margin_left = margin
		style.content_margin_right = margin
		_pause_button.add_theme_stylebox_override(state, style)
	_pause_button.custom_minimum_size = Vector2(side, side)
	for icon: StringName in ICON_COLORS:
		_pause_button.add_theme_color_override(icon, button.get_theme_color(ICON_COLORS[icon]))


## Whether entry `index` of the list shows without scrolling (for tests and probes).
func is_row_in_view(index: int) -> bool:
	var button: Button = _buttons[index]
	var top: float = button.position.y - _scroll.scroll_vertical
	return top >= -0.5 and top + button.size.y <= _scroll.size.y + 0.5


## Scrolls the list so entry `index` shows.
func _scroll_to(index: int) -> void:
	if index < 0 or index >= _buttons.size():
		return
	var button: Button = _buttons[index]
	var top: float = button.position.y
	var bottom: float = top + button.size.y
	if top < _scroll.scroll_vertical:
		_scroll.scroll_vertical = int(top)
	elif bottom > _scroll.scroll_vertical + _scroll.size.y:
		_scroll.scroll_vertical = int(ceilf(bottom - _scroll.size.y))


## The theme's style of a button `state` with an amber frame.
func _selected_style(button: Button, state: StringName) -> StyleBox:
	if not _selected_styles.has(state):
		var style: StyleBox = button.get_theme_stylebox(state).duplicate()
		var flat := style as StyleBoxFlat
		if flat:
			flat.border_color = CardPalette.STATUS
			flat.set_border_width_all(3)
		_selected_styles[state] = style
	return _selected_styles[state]


func _on_pause_pressed() -> void:
	var npc := station as Npc
	if npc:
		npc.talk.toggle_auto_pause()


func _on_button_pressed(index: int) -> void:
	var npc := station as Npc
	if not npc:
		return
	if npc.talk.topic:
		# "Continue"/"Done", or "Back".
		if index == 0:
			npc.talk.advance()
		else:
			npc.talk.leave_topic()
		return
	npc.talk.set_choice(index)
	npc.talk.press()
