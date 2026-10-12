class_name ArmoryMenu
extends PanelContainer
## The loadout, picked on the console in the armory: one row per weapon of the game (`catalog`)
## with its name, how it plays, ranged or melee, and a button per loadout slot. Weapons the player
## doesn't own yet are greyed out ("Locked"). Pressing a slot puts the weapon there (swapping
## with its other slot) or takes it out again. It shows the loadout of the player using the
## console (else the first player's) and is locked while a mission is underway.

const LOCKED_COLOR := Color(1.0, 1.0, 1.0, 0.35)

## Every weapon of the game, in the order of the rows.
@export var catalog: Arsenal

## The player whose loadout it shows, or null.
var player: Player
## The mission that locks it while underway; found in the scene tree when not set.
var mission: Mission

## Slot buttons per weapon, in slot order.
var _buttons: Dictionary[WeaponType, Array] = {}
## The owned weapons the rows were built for.
var _owned: Array[WeaponType] = []

@onready var _rows: VBoxContainer = %Rows
@onready var _status: Label = %Status
@onready var _close: Button = %Close


func _ready() -> void:
	_close.pressed.connect(_on_close_pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and player:
		_build_rows()


func _process(_delta: float) -> void:
	if not mission:
		mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	var shown: Player = _current_player()
	if shown != player or (shown and shown.arsenal.weapons != _owned):
		player = shown
		_build_rows()
	_update()


## The slot buttons of `weapon_type` (in slot order), or an empty array.
func get_slot_buttons(weapon_type: WeaponType) -> Array[Button]:
	var buttons: Array[Button] = []
	if weapon_type in _buttons:
		buttons.assign(_buttons[weapon_type])
	return buttons


## Whether loadouts can't change right now.
func is_locked() -> bool:
	return mission != null and mission.is_underway()


func _current_player() -> Player:
	var panel: WorldPanel = WorldPanel.showing(self)
	if panel and panel.user:
		return panel.user
	return get_tree().get_first_node_in_group(Player.GROUP) as Player


func _build_rows() -> void:
	var had_focus: bool = _rows.get_viewport().gui_get_focus_owner() != null
	for row: Node in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	_buttons.clear()
	_owned = player.arsenal.weapons.duplicate() if player else []
	if not player or not catalog:
		return
	for weapon_type: WeaponType in catalog.weapons:
		_rows.add_child(_row(weapon_type))
	if had_focus:
		var first: Control = _rows.find_next_valid_focus()
		if first:
			first.grab_focus()


func _row(weapon_type: WeaponType) -> Control:
	var owned: bool = player.arsenal.owns(weapon_type)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 0)
	var title: Label = _label(tr(weapon_type.display_name))
	text.add_child(title)
	var description: Label = _label(tr(weapon_type.description))
	description.add_theme_font_size_override(&"font_size", 22)
	description.modulate = Color(1.0, 1.0, 1.0, 0.7)
	text.add_child(description)
	row.add_child(text)
	var kind: Label = _label(_kind_name(weapon_type) if owned else tr("Locked"))
	kind.custom_minimum_size.x = 130.0
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(kind)
	var buttons: Array[Button] = []
	for slot: int in player.settings.loadout_slots:
		var button := Button.new()
		button.text = str(slot + 1)
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(64.0, 0.0)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(_on_slot_pressed.bind(weapon_type, slot))
		buttons.append(button)
		row.add_child(button)
	_buttons[weapon_type] = buttons
	if not owned:
		text.modulate = LOCKED_COLOR
		kind.modulate = LOCKED_COLOR
	return row


func _kind_name(weapon_type: WeaponType) -> String:
	return tr("Melee") if weapon_type.kind == WeaponType.Kind.MELEE else tr("Ranged")


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	# Texts set from code are translated already.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label


## Shows each weapon's slot and what can be pressed right now.
func _update() -> void:
	var locked: bool = is_locked()
	for weapon_type: WeaponType in _buttons:
		var owned: bool = player.arsenal.owns(weapon_type)
		var slot_now: int = player.loadout.slot_of(weapon_type)
		var buttons: Array = _buttons[weapon_type]
		for slot: int in buttons.size():
			var button: Button = buttons[slot]
			button.set_pressed_no_signal(slot == slot_now)
			button.disabled = locked or not owned
	if locked:
		_status.text = tr("Locked until everyone is back aboard.")
	elif not player:
		_status.text = ""
	else:
		_status.text = tr("Pick the weapons for the next mission.")


func _on_slot_pressed(weapon_type: WeaponType, slot: int) -> void:
	if is_locked() or not player.arsenal.owns(weapon_type):
		return
	if player.loadout.get_weapon(slot) == weapon_type:
		player.loadout.assign(slot, null)
	else:
		player.loadout.assign(slot, weapon_type)
	_update()


func _on_close_pressed() -> void:
	var panel: WorldPanel = WorldPanel.showing(self)
	if panel:
		panel.close()
