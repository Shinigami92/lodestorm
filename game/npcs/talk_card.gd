class_name TalkCard
extends StationCard
## The holo card beside an NPC while a player talks to them (`Npc`): their name and role, then
## either the open topics and "Goodbye" (an amber dot on topics nobody has heard yet), or while a
## topic is told its title, how far it is ("2 / 3") and "Continue" ("Done" on the last line) and
## "Back". The button `interact` presses has an amber frame (not the focus, see `LoadoutCard`).
## Past `MAX_ROWS` entries the list scrolls, keeping the framed one in view (an NPC with many
## topics, like the bartender's rumors about every planet).

## Button states framed amber on the selected button.
const SELECTED_STATES: Array[StringName] = [
	&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"
]
## Marks a topic nobody has heard yet.
const NEW_DOT: String = "●  "
## The most entries the list shows at once; more scroll.
const MAX_ROWS: int = 7

var _buttons: Array[Button] = []
## The amber-framed styles of the selected button, per state.
var _selected_styles: Dictionary[StringName, StyleBox] = {}

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
	var told: Topic = npc.topic
	_topic_title.visible = told != null
	_progress.visible = told != null
	if told:
		_topic_title.text = tr(told.title)
		_progress.text = "%d / %d" % [npc.line + 1, told.lines.size()]
		var last: bool = npc.line + 1 >= told.lines.size()
		_show_buttons([tr("Done") if last else tr("Continue"), tr("Back")], [false, false], 0)
		return
	var texts: Array[String] = []
	var new: Array[bool] = []
	for choice: Topic in npc.get_choices():
		texts.append(tr(choice.title))
		new.append(npc.is_new(choice))
	texts.append(tr("Goodbye"))
	new.append(false)
	_show_buttons(texts, new, npc.choice)


func press_primary() -> bool:
	var npc := station as Npc
	if not npc:
		return false
	npc.press()
	return true


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


func _on_button_pressed(index: int) -> void:
	var npc := station as Npc
	if not npc:
		return
	if npc.topic:
		# "Continue"/"Done", or "Back".
		if index == 0:
			npc.advance()
		else:
			npc.leave_topic()
		return
	npc.set_choice(index)
	npc.press()
