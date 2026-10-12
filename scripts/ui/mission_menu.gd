class_name MissionMenu
extends PanelContainer
## The missions on offer, shown on the console at the bridge's holo table: one row per mission
## with its location, timer, difficulty and the biome's ores (from common to rare). Picking one
## shows its location on the hologram, with the ore fields in their colors; "Set course" then flies
## the ship there. No picking during the flight, and once the ramp is down for a mission, it's
## locked until the run ends.

## Text colors of the difficulties (easy, normal, hard).
const DIFFICULTY_COLORS: Array[Color] = [
	Color(0.45, 0.95, 0.55), Color(1.0, 0.75, 0.3), Color(1.0, 0.4, 0.35)
]
const ORE_CHIP_SIZE := Vector2(22.0, 22.0)

## The mission whose offers it shows; found in the scene tree when not set.
var mission: Mission

## The offers the rows show, and each one's button.
var _shown: Array[MissionBrief] = []
var _buttons: Dictionary[MissionBrief, Button] = {}

@onready var _offers: VBoxContainer = %Offers
@onready var _status: Label = %Status
@onready var _set_course: Button = %SetCourse
@onready var _close: Button = %Close


func _ready() -> void:
	_set_course.pressed.connect(_on_set_course_pressed)
	_close.pressed.connect(_on_close_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and mission:
		_build_rows()
		_refresh()


func _process(_delta: float) -> void:
	if not mission:
		mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
		if not mission:
			return
		mission.offers_changed.connect(_refresh)
		_refresh()
	_update_status()


## The button that picks `offer`, or null.
func get_button(offer: MissionBrief) -> Button:
	return _buttons.get(offer) as Button


## The button that sets course for the picked mission.
func get_set_course_button() -> Button:
	return _set_course


func _refresh() -> void:
	if mission.offers != _shown:
		_build_rows()
	for offer: MissionBrief in _buttons:
		_buttons[offer].set_pressed_no_signal(offer == mission.previewed)
	_update_status()


func _build_rows() -> void:
	var had_focus: bool = _offers.get_viewport().gui_get_focus_owner() in _buttons.values()
	for row: Node in _offers.get_children():
		_offers.remove_child(row)
		row.queue_free()
	_buttons.clear()
	_shown = mission.offers.duplicate()
	for offer: MissionBrief in _shown:
		_offers.add_child(_row(offer))
	if had_focus and not _shown.is_empty():
		_buttons[_shown[0]].grab_focus()


func _row(offer: MissionBrief) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 24)
	var button := Button.new()
	button.text = offer.location_name()
	# Texts set from code are translated already.
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(_on_offer_pressed.bind(offer))
	_buttons[offer] = button
	row.add_child(button)
	row.add_child(_label(tr("%d min") % roundi(mission.settings.duration * offer.length / 60.0)))
	var difficulty: Label = _label(offer.difficulty_name())
	difficulty.add_theme_color_override(&"font_color", DIFFICULTY_COLORS[offer.difficulty])
	row.add_child(difficulty)
	var ores := HBoxContainer.new()
	ores.custom_minimum_size.x = 3 * ORE_CHIP_SIZE.x + 2 * 6.0
	ores.add_theme_constant_override(&"separation", 6)
	ores.alignment = BoxContainer.ALIGNMENT_END
	if offer.biome:
		for ore_type: OreType in offer.biome.ores:
			var chip := ColorRect.new()
			chip.color = ore_type.color
			chip.custom_minimum_size = ORE_CHIP_SIZE
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ores.add_child(chip)
	row.add_child(ores)
	return row


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.custom_minimum_size.x = 110.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _update_status() -> void:
	var can_select: bool = mission.can_select()
	for offer: MissionBrief in _buttons:
		_buttons[offer].disabled = not can_select
	_set_course.disabled = not mission.can_confirm()
	if mission.flight.is_flying():
		_status.text = tr("In flight: gear up and head for the ramp.")
	elif not can_select:
		_status.text = tr("Locked until everyone is back aboard.")
	elif mission.is_preparing():
		_status.text = tr("Scanning the location...")
	elif mission.can_confirm():
		_status.text = tr("Set course to fly there.")
	elif mission.brief:
		_status.text = tr("Landed: lower the ramp in the cargo bay.")
	else:
		_status.text = tr("Pick a mission to see it on the hologram.")


func _on_offer_pressed(offer: MissionBrief) -> void:
	if not mission.preview(offer):
		_refresh()


func _on_set_course_pressed() -> void:
	mission.confirm()
	_refresh()


func _on_close_pressed() -> void:
	var panel: WorldPanel = WorldPanel.showing(self)
	if panel:
		panel.close()
