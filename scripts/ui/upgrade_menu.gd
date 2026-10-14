class_name UpgradeMenu
extends PanelContainer
## An upgrade station's menu, on the console in its upgrade room: one row per upgrade with its
## name, what it improves, the MK level and how much the next one improves (compared to MK1), the
## next level's cost in ore and a button that buys it with ore from the ship's hold. The header
## shows what the hold has of the ores the upgrades cost. Costs the hold can't pay show in red and
## can't be bought; upgrades of weapons the player doesn't own yet are greyed out ("Locked"). It
## shows the upgrades of the player using the console (else the first player's) and is locked
## while a mission is underway.

const LOCKED_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const MISSING_COLOR := Color(1.0, 0.4, 0.35)
const ORE_CHIP_SIZE := Vector2(22.0, 22.0)

## Rows for the upgrades of these weapons (in this order, each with its parts: damage, magazine),
## locked unless the player owns the weapon.
@export var weapons: Arsenal
## Rows for these upgrades, after the weapons'.
@export var upgrades: Array[Upgrade] = []

## The player whose upgrades it shows, or null.
var player: Player
## The mission that locks it while underway; found in the scene tree when not set.
var mission: Mission
## The ship whose hold pays; the one the console is in when not set.
var ship: Ship

## The weapon per weapon upgrade row (other rows have none).
var _weapon_of: Dictionary[Upgrade, WeaponType] = {}
## Buy button, MK label and cost labels (per ore type) per row.
var _buttons: Dictionary[Upgrade, Button] = {}
var _mk_labels: Dictionary[Upgrade, Label] = {}
var _cost_labels: Dictionary[Upgrade, Dictionary] = {}
## What the rows were built for: the owned weapons and the MK levels.
var _owned: Array[WeaponType] = []
var _shown_mk: Dictionary[Upgrade, int] = {}
## Hold amount label per ore type in the header.
var _hold_labels: Dictionary[OreType, Label] = {}

@onready var _rows: VBoxContainer = %Rows
@onready var _hold: HBoxContainer = %Hold
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
	if not ship:
		ship = _find_ship()
	var shown: Player = _current_player()
	if shown != player or (shown and (shown.arsenal.weapons != _owned or _levels_changed())):
		player = shown
		_build_rows()
	_update()


## Every upgrade it lists, in row order.
func listed() -> Array[Upgrade]:
	var all: Array[Upgrade] = []
	if weapons:
		for weapon_type: WeaponType in weapons.weapons:
			all.append_array(weapon_type.get_upgrades())
	all.append_array(upgrades)
	return all


## The button that buys the next level of `upgrade`, or null.
func get_buy_button(upgrade: Upgrade) -> Button:
	return _buttons.get(upgrade) as Button


## Whether nothing can be bought right now.
func is_locked() -> bool:
	return mission != null and mission.is_underway()


## Whether `player` can buy the next level of `upgrade` right now.
func can_buy(upgrade: Upgrade) -> bool:
	if is_locked() or not player or not ship or not _available(upgrade):
		return false
	var level: UpgradeLevel = player.upgrades.next_level(upgrade)
	return level != null and ship.can_pay(level.cost)


## Buys the next level of `upgrade` for the player, paid from the hold. Returns whether it did.
func buy(upgrade: Upgrade) -> bool:
	if not can_buy(upgrade):
		return false
	if not ship.pay(player.upgrades.next_level(upgrade).cost):
		return false
	player.upgrades.raise(upgrade)
	_build_rows()
	return true


func _current_player() -> Player:
	var panel: WorldPanel = WorldPanel.showing(self)
	if panel and panel.user:
		return panel.user
	return get_tree().get_first_node_in_group(Player.GROUP) as Player


func _find_ship() -> Ship:
	var panel: WorldPanel = WorldPanel.showing(self)
	if panel:
		return Ship.nearest(get_tree(), panel.global_position)
	return get_tree().get_first_node_in_group(Ship.GROUP) as Ship


## Whether the player has the upgrade's weapon (or it's not a weapon's).
func _available(upgrade: Upgrade) -> bool:
	var weapon_type: WeaponType = _weapon_of.get(upgrade)
	return not weapon_type or (player and player.arsenal.owns(weapon_type))


func _levels_changed() -> bool:
	for upgrade: Upgrade in _shown_mk:
		if player.upgrades.mk(upgrade) != _shown_mk[upgrade]:
			return true
	return false


func _build_rows() -> void:
	var had_focus: bool = _rows.get_viewport().gui_get_focus_owner() != null
	for row: Node in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	_weapon_of.clear()
	_buttons.clear()
	_mk_labels.clear()
	_cost_labels.clear()
	_shown_mk.clear()
	_owned = player.arsenal.weapons.duplicate() if player else []
	_build_hold()
	if not player:
		return
	if weapons:
		for weapon_type: WeaponType in weapons.weapons:
			for part: Upgrade in weapon_type.get_upgrades():
				_weapon_of[part] = weapon_type
	for upgrade: Upgrade in listed():
		_rows.add_child(_row(upgrade))
	if had_focus:
		var first: Control = _rows.find_next_valid_focus()
		if first:
			first.grab_focus()


func _row(upgrade: Upgrade) -> Control:
	var mk: int = player.upgrades.mk(upgrade)
	_shown_mk[upgrade] = mk
	var next: UpgradeLevel = upgrade.level_after(mk)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 0)
	text.add_child(_label(tr(upgrade.display_name)))
	var description: Label = _small_label(tr(upgrade.description))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(description)
	row.add_child(text)
	var level := VBoxContainer.new()
	level.custom_minimum_size.x = 150.0
	level.add_theme_constant_override(&"separation", 0)
	var mk_label: Label = _label("")
	mk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mk_labels[upgrade] = mk_label
	level.add_child(mk_label)
	var effect: Label = _small_label(_effect_text(upgrade, mk))
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level.add_child(effect)
	row.add_child(level)
	var cost := HBoxContainer.new()
	cost.custom_minimum_size.x = 170.0
	cost.alignment = BoxContainer.ALIGNMENT_END
	cost.add_theme_constant_override(&"separation", 6)
	var cost_labels: Dictionary[OreType, Label] = {}
	if next:
		for ore_type: OreType in next.cost:
			cost.add_child(_chip(ore_type))
			var amount: Label = _label(str(next.cost[ore_type]))
			amount.add_theme_font_size_override(&"font_size", 24)
			cost.add_child(amount)
			cost_labels[ore_type] = amount
	_cost_labels[upgrade] = cost_labels
	row.add_child(cost)
	var button := Button.new()
	button.text = tr("Upgrade") if next else tr("Max")
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.custom_minimum_size.x = 190.0
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(buy.bind(upgrade))
	_buttons[upgrade] = button
	row.add_child(button)
	if not _available(upgrade):
		row.modulate = LOCKED_COLOR
	return row


## How much the upgrade improves compared to MK1: at the next level, or at the highest.
func _effect_text(upgrade: Upgrade, mk: int) -> String:
	if mk < upgrade.max_mk():
		return tr("next: +%d %%") % _bonus(upgrade, mk + 1)
	return "+%d %%" % _bonus(upgrade, mk)


## The hold's ores in the header: every ore type a listed upgrade costs, in the order they appear.
func _build_hold() -> void:
	for node: Node in _hold.get_children():
		_hold.remove_child(node)
		node.queue_free()
	_hold_labels.clear()
	if listed().is_empty():
		return
	var title: Label = _label(tr("Hold"))
	title.modulate = Color(1.0, 1.0, 1.0, 0.7)
	_hold.add_child(title)
	for upgrade: Upgrade in listed():
		for level: UpgradeLevel in upgrade.levels:
			for ore_type: OreType in level.cost:
				if ore_type in _hold_labels:
					continue
				_hold.add_child(_chip(ore_type))
				var amount: Label = _label("0")
				amount.custom_minimum_size.x = 64.0
				_hold.add_child(amount)
				_hold_labels[ore_type] = amount


## Shows the MK levels, the hold, what the hold can pay and what can be pressed right now.
func _update() -> void:
	for ore_type: OreType in _hold_labels:
		var stored: float = ship.hold.get(ore_type, 0.0) if ship else 0.0
		_hold_labels[ore_type].text = str(floori(stored))
	for upgrade: Upgrade in _buttons:
		var available: bool = _available(upgrade)
		var mk: int = player.upgrades.mk(upgrade)
		_mk_labels[upgrade].text = (
			"MK%d / %d" % [mk, upgrade.max_mk()] if available else tr("Locked")
		)
		var next: UpgradeLevel = player.upgrades.next_level(upgrade)
		var cost_labels: Dictionary = _cost_labels[upgrade]
		for ore_type: OreType in cost_labels:
			var label: Label = cost_labels[ore_type]
			var stored: float = ship.hold.get(ore_type, 0.0) if ship else 0.0
			if next and stored < next.cost.get(ore_type, 0):
				label.add_theme_color_override(&"font_color", MISSING_COLOR)
			else:
				label.remove_theme_color_override(&"font_color")
		_buttons[upgrade].disabled = not can_buy(upgrade)
	if is_locked():
		_status.text = tr("Locked until everyone is back aboard.")
	elif not player:
		_status.text = ""
	else:
		_status.text = tr("Upgrades are paid with ore from the hold.")


func _chip(ore_type: OreType) -> ColorRect:
	var chip := ColorRect.new()
	chip.color = ore_type.color
	chip.custom_minimum_size = ORE_CHIP_SIZE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return chip


func _small_label(text: String) -> Label:
	var label: Label = _label(text)
	label.add_theme_font_size_override(&"font_size", 22)
	label.modulate = Color(1.0, 1.0, 1.0, 0.7)
	return label


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	# Texts set from code are translated already.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label


func _on_close_pressed() -> void:
	var panel: WorldPanel = WorldPanel.showing(self)
	if panel:
		panel.close()


static func _bonus(upgrade: Upgrade, mk: int) -> int:
	return roundi((upgrade.multiplier(mk) - 1.0) * 100.0)
