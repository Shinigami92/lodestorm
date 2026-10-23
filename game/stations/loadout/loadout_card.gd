class_name LoadoutCard
extends StationCard
## The holo card of a locker (`LoadoutStation`): the selected weapon's name, how it plays, what
## it is ("Assault rifle"; "Locked" when the player doesn't own it yet), the MK level of each of
## its parts as pips and a button per slot, pressed where the weapon is. The slot
## `interact` uses has an amber frame (not the focus: moving the focus every frame would cancel a
## mouse press on the other button). Below, what the slots are for, or while a mission is underway
## why nothing changes.

const PIP_LIT := Color(0.3, 0.85, 1.0)
const PIP_DARK := Color(0.12, 0.18, 0.22)
const PIP_SIZE := Vector2(22.0, 12.0)
const SELECTED_SLOT_COLOR := Color(1.0, 0.75, 0.3)
## Button states framed amber on the selected slot.
const SLOT_STATES: Array[StringName] = [
	&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"
]

## The weapon shown, or null.
var weapon_type: WeaponType

var _slot_buttons: Array[Button] = []
## The amber-framed styles of the selected slot's button, per state.
var _selected_styles: Dictionary[StringName, StyleBox] = {}
## What the level rows show: the weapon, its MK levels and the language.
var _levels_shown: Array = []

@onready var _title: Label = %Title
@onready var _description: Label = %Description
@onready var _kind: Label = %Kind
@onready var _levels: GridContainer = %Levels
@onready var _status: Label = %Status
@onready var _slots: HBoxContainer = %Slots
@onready var _close: Button = %Close


func _ready() -> void:
	_close.pressed.connect(_on_close_pressed)


func show_part(part: StationPart) -> void:
	var locker := station as LoadoutStation
	var shown := part.item as WeaponType if part else null
	if not shown or not locker or not locker.user:
		show_weapon(null)
		return
	var player: Player = locker.user
	show_weapon(
		shown,
		player.upgrades,
		player.arsenal.owns(shown),
		locker.is_locked(),
		player.loadout.slot_of(shown),
		locker.selected_slot,
		player.settings.loadout_slots
	)


## Shows `shown` (null: nothing) with the MK levels in `upgrades`. `owned`: whether the player has
## it; `locked`: whether a mission is underway; `slot`: where it is in the loadout (-1: nowhere);
## `selected_slot`: the slot `interact` uses; `slots`: how many there are.
func show_weapon(
	shown: WeaponType,
	upgrades: Upgrades = null,
	owned: bool = true,
	locked: bool = false,
	slot: int = -1,
	selected_slot: int = 0,
	slots: int = 2
) -> void:
	weapon_type = shown
	visible = shown != null
	if not shown:
		return
	_title.text = shown.display_name
	_description.text = tr(shown.description)
	_kind.text = tr(shown.class_word) if owned else tr("Locked")
	_show_levels(shown, upgrades if upgrades else Upgrades.new(), owned)
	# Why nothing changes, else what the slots are for.
	_status.text = (
		tr("Locked until everyone is back aboard.")
		if locked
		else tr("Slots 1 and 2 go along on the next mission; one weapon always does.")
	)
	_status.add_theme_color_override(
		&"font_color", CardPalette.STATUS if locked else CardPalette.HINT
	)
	_show_slots(slots, slot, selected_slot, owned and not locked)
	for dimmed: CanvasItem in [_title, _description, _levels]:
		dimmed.modulate = Color.WHITE if owned else CardPalette.DIMMED


func press_primary() -> bool:
	var locker := station as LoadoutStation
	return (
		locker != null and weapon_type != null and locker.toggle(weapon_type, locker.selected_slot)
	)


## The button of `slot` (for tests and probes), or null.
func get_slot_button(slot: int) -> Button:
	return _slot_buttons[slot] if slot >= 0 and slot < _slot_buttons.size() else null


## One row per part (damage, capacity, ...): its name and its MK level as pips.
func _show_levels(shown: WeaponType, upgrades: Upgrades, owned: bool) -> void:
	var levels: Array = [shown, TranslationServer.get_locale()]
	for part: WeaponPart in shown.parts:
		levels.append(upgrades.mk(part) if owned else 0)
	if levels == _levels_shown:
		return
	_levels_shown = levels
	for node: Node in _levels.get_children():
		_levels.remove_child(node)
		node.queue_free()
	for upgrade: WeaponPart in shown.parts:
		var label: Label = _label(tr(upgrade.display_name))
		label.add_theme_font_size_override(&"font_size", 20)
		_levels.add_child(label)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override(&"separation", 6)
		var mk: int = upgrades.mk(upgrade) if owned else 0
		for i: int in upgrade.max_mk():
			var pip := ColorRect.new()
			pip.custom_minimum_size = PIP_SIZE
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pip.color = PIP_LIT if i < mk else PIP_DARK
			pips.add_child(pip)
		_levels.add_child(pips)


func _show_slots(slots: int, slot: int, selected_slot: int, enabled: bool) -> void:
	while _slot_buttons.size() < slots:
		var button := Button.new()
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_slot_pressed.bind(_slot_buttons.size()))
		_slots.add_child(button)
		_slot_buttons.append(button)
	for i: int in _slot_buttons.size():
		var button: Button = _slot_buttons[i]
		button.text = tr("Slot %d") % (i + 1)
		button.set_pressed_no_signal(i == slot)
		button.disabled = not enabled
		for state: StringName in SLOT_STATES:
			if i == selected_slot:
				button.add_theme_stylebox_override(state, _selected_style(button, state))
			else:
				button.remove_theme_stylebox_override(state)


## The theme's style of a button `state` with an amber frame.
func _selected_style(button: Button, state: StringName) -> StyleBox:
	if not _selected_styles.has(state):
		var style: StyleBox = button.get_theme_stylebox(state).duplicate()
		var flat := style as StyleBoxFlat
		if flat:
			flat.border_color = SELECTED_SLOT_COLOR
			flat.set_border_width_all(3)
		_selected_styles[state] = style
	return _selected_styles[state]


func _on_slot_pressed(slot: int) -> void:
	var locker := station as LoadoutStation
	if locker and weapon_type:
		locker.toggle(weapon_type, slot)


func _on_close_pressed() -> void:
	if station:
		station.close()
