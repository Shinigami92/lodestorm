class_name UpgradeCard
extends StationCard
## The holo card of an `UpgradeStation`: the selected upgrade's name and what it improves, its MK
## level as pips (like the pips on the weapons and the helmet), how much the next level improves
## (compared to MK1), the next level's cost per ore next to what the hold has of it (red where it's
## short), and "Upgrade". A weapon's upgrade the player can't buy yet says "Locked", and while a
## mission is underway it says why nothing can be bought.

## Dims what a locked upgrade would bring (the card itself and "Locked" stay readable).
const LOCKED_COLOR := Color(1.0, 1.0, 1.0, 0.45)
const MISSING_COLOR := Color(1.0, 0.4, 0.35)
const PIP_LIT := Color(0.3, 0.85, 1.0)
const PIP_DARK := Color(0.12, 0.18, 0.22)
const PIP_SIZE := Vector2(30.0, 14.0)
const ORE_CHIP_SIZE := Vector2(22.0, 22.0)

## The upgrade shown, or null.
var upgrade: Upgrade

## The level whose cost the cost row shows, and its amount label per ore type.
var _cost_level: UpgradeLevel
var _cost_labels: Dictionary[OreType, Label] = {}

@onready var _title: Label = %Title
@onready var _pips: HBoxContainer = %Pips
@onready var _description: Label = %Description
@onready var _effect: Label = %Effect
@onready var _cost: HFlowContainer = %Cost
@onready var _cost_row: HFlowContainer = %CostRow
@onready var _status: Label = %Status
@onready var _buy: Button = %Buy
@onready var _close: Button = %Close


func _ready() -> void:
	_buy.pressed.connect(press_primary)
	_close.pressed.connect(_on_close_pressed)


func show_part(part: StationPart) -> void:
	var upgrade_station := station as UpgradeStation
	var shown := part.item as Upgrade if part else null
	if not shown or not upgrade_station or not upgrade_station.user:
		show_upgrade(null)
		return
	var hold: Dictionary[OreType, float] = {}
	if upgrade_station.ship:
		hold = upgrade_station.ship.hold
	show_upgrade(
		shown,
		upgrade_station.user.upgrades.mk(shown),
		hold,
		upgrade_station.is_available(shown),
		upgrade_station.is_locked(),
		upgrade_station.can_buy(shown)
	)


## Shows `shown` at MK `mk` (null: nothing). `hold`: what the hold has; `available`: whether the
## player has its weapon; `locked`: whether a mission is underway; `can_buy`: whether its next
## level can be bought right now.
func show_upgrade(
	shown: Upgrade,
	mk: int = 1,
	hold: Dictionary[OreType, float] = {},
	available: bool = true,
	locked: bool = false,
	can_buy: bool = false
) -> void:
	upgrade = shown
	visible = shown != null
	if not shown:
		return
	_title.text = tr(shown.display_name)
	_description.text = tr(shown.description)
	_show_pips(mk if available else 0, shown.max_mk())
	var next: UpgradeLevel = shown.level_after(mk)
	if not available:
		_effect.text = tr("Locked")
	elif next:
		_effect.text = tr("next: +%d %%") % _bonus(shown, mk + 1)
	else:
		_effect.text = "+%d %%" % _bonus(shown, mk)
	_show_cost(next, hold)
	_status.visible = locked
	_status.text = tr("Locked until everyone is back aboard.")
	_buy.text = tr("Upgrade") if next else tr("Max")
	_buy.disabled = not can_buy
	for dimmed: CanvasItem in [_title, _description, _pips, _cost_row]:
		dimmed.modulate = Color.WHITE if available else LOCKED_COLOR


func press_primary() -> bool:
	var upgrade_station := station as UpgradeStation
	return upgrade_station != null and upgrade_station.buy(upgrade)


## The buy button (for tests and probes).
func get_buy_button() -> Button:
	return _buy


func _show_pips(mk: int, max_mk: int) -> void:
	while _pips.get_child_count() < max_mk:
		var pip := ColorRect.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_pips.add_child(pip)
	while _pips.get_child_count() > max_mk:
		var last: Node = _pips.get_child(-1)
		_pips.remove_child(last)
		last.queue_free()
	for i: int in max_mk:
		(_pips.get_child(i) as ColorRect).color = PIP_LIT if i < mk else PIP_DARK


## The next level's cost per ore, each as "cost / in the hold"; red where the hold is short.
func _show_cost(next: UpgradeLevel, hold: Dictionary[OreType, float]) -> void:
	if next != _cost_level:
		_cost_level = next
		for node: Node in _cost.get_children():
			_cost.remove_child(node)
			node.queue_free()
		_cost_labels.clear()
		if next:
			for ore_type: OreType in next.cost:
				var chip := ColorRect.new()
				chip.color = ore_type.color
				chip.custom_minimum_size = ORE_CHIP_SIZE
				chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				_cost.add_child(chip)
				var amount: Label = _label("")
				_cost.add_child(amount)
				_cost_labels[ore_type] = amount
	if not next:
		return
	for ore_type: OreType in _cost_labels:
		var in_hold: float = hold.get(ore_type, 0.0)
		var stored: int = floori(in_hold)
		var label: Label = _cost_labels[ore_type]
		label.text = "%d / %d" % [next.cost[ore_type], stored]
		if stored < next.cost[ore_type]:
			label.add_theme_color_override(&"font_color", MISSING_COLOR)
		else:
			label.remove_theme_color_override(&"font_color")


func _on_close_pressed() -> void:
	if station:
		station.close()


static func _bonus(shown: Upgrade, mk: int) -> int:
	return roundi((shown.multiplier(mk) - 1.0) * 100.0)
