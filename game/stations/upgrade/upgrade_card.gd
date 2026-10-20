class_name UpgradeCard
extends StationCard
## The holo card of an `UpgradeStation`: the selected upgrade's name and what it improves, its MK
## level as pips (like the pips on the weapons and the helmet), how much the next level improves
## (compared to MK1), the next level's cost per ore next to what the hold has of it (red where it's
## short), and "Upgrade". A weapon's upgrade the player can't buy yet says "Locked", levels beyond
## the ship's reach show as faint pips and the card says which heat shield plate brings the next
## one, and while a mission is underway it says why nothing can be bought. A weapon's part is
## titled with the weapon's name. On the workbench, a weapon the player doesn't own shows what
## building it costs and "Build" (with its blueprint, see `WeaponStation.build`); a weapon selected
## on the rack shows what it is and "Lay on the bench".

## Dims what a locked upgrade would bring (the card itself and "Locked" stay readable).
const LOCKED_COLOR := Color(1.0, 1.0, 1.0, 0.45)
const PIP_LIT := Color(0.3, 0.85, 1.0)
const PIP_DARK := Color(0.12, 0.18, 0.22)
## Levels beyond the ship's reach (they come with the next planets).
const PIP_OUT_OF_REACH := Color(0.12, 0.18, 0.22, 0.35)
const PIP_SIZE := Vector2(20.0, 14.0)

## The upgrade shown, or null.
var upgrade: Upgrade
## The weapon to build or to lay on the bench shown, or null.
var weapon_type: WeaponType
## Whether `weapon_type` is shown on the rack, to lay it on the bench (else to build it).
var picking: bool = false

@onready var _title: Label = %Title
@onready var _pips: HBoxContainer = %Pips
@onready var _description: Label = %Description
@onready var _effect: Label = %Effect
@onready var _cost: OreCost = %Cost
@onready var _cost_row: HFlowContainer = %CostRow
@onready var _status: Label = %Status
@onready var _buy: Button = %Buy
@onready var _close: Button = %Close


func _ready() -> void:
	_buy.pressed.connect(press_primary)
	_close.pressed.connect(_on_close_pressed)


func show_part(part: StationPart) -> void:
	var upgrade_station := station as UpgradeStation
	var hold: Dictionary[OreType, float] = {}
	if upgrade_station and upgrade_station.ship:
		hold = upgrade_station.ship.hold
	var weapon_station := station as WeaponStation
	var to_build := part.item as WeaponType if part else null
	if to_build and weapon_station and part in weapon_station.get_rack_parts():
		show_pick(to_build, not weapon_station.user or weapon_station.user.arsenal.owns(to_build))
		return
	if to_build and weapon_station and weapon_station.user:
		show_build(
			to_build,
			hold,
			weapon_station.user.arsenal.has_blueprint(to_build),
			weapon_station.is_locked(),
			weapon_station.can_build(to_build)
		)
		return
	var shown := part.item as Upgrade if part else null
	if not shown or not upgrade_station or not upgrade_station.user:
		show_upgrade(null)
		return
	var weapon: WeaponType = upgrade_station.get_weapon(shown)
	show_upgrade(
		shown,
		upgrade_station.user.upgrades.mk(shown),
		hold,
		upgrade_station.is_available(shown),
		upgrade_station.is_locked(),
		upgrade_station.can_buy(shown),
		upgrade_station.upgrade_cap(),
		weapon.display_name if weapon else ""
	)


## Shows `shown` at MK `mk` (null: nothing). `hold`: what the hold has; `available`: whether the
## player has its weapon; `locked`: whether a mission is underway; `can_buy`: whether its next
## level can be bought right now; `cap`: the highest MK level the ship's heat shield allows;
## `weapon_name`: the name of the weapon it's a part of (empty: none).
func show_upgrade(
	shown: Upgrade,
	mk: int = 1,
	hold: Dictionary[OreType, float] = {},
	available: bool = true,
	locked: bool = false,
	can_buy: bool = false,
	cap: int = 99,
	weapon_name: String = ""
) -> void:
	upgrade = shown
	weapon_type = null
	picking = false
	visible = shown != null
	if not shown:
		return
	_cost_row.visible = true
	_title.text = tr(shown.display_name)
	if weapon_name:
		_title.text = "%s — %s" % [weapon_name, _title.text]
	_description.text = tr(shown.description)
	_pips.visible = true
	show_pips(_pips, mk if available else 0, shown.max_mk(), cap)
	var next: UpgradeLevel = shown.level_after(mk)
	if not available:
		_effect.text = tr("Locked")
	elif next:
		_effect.text = tr("next: +%d %%") % _bonus(shown, mk + 1)
	else:
		_effect.text = "+%d %%" % _bonus(shown, mk)
	_cost.show_cost(shown.cost_of(mk + 1), hold)
	var beyond_reach: bool = next != null and available and mk >= cap
	_status.visible = locked or beyond_reach
	if locked:
		_status.text = tr("Locked until everyone is back aboard.")
	elif beyond_reach:
		_status.text = (
			tr("MK%d comes with heat shield MK%d (engine room).")
			% [mk + 1, mk + 1 - CelestialBody.MK_ABOVE_TIER]
		)
	_buy.text = tr("Upgrade") if next else tr("Max")
	_buy.disabled = not can_buy
	for dimmed: CanvasItem in [_title, _description, _pips, _cost_row]:
		dimmed.modulate = Color.WHITE if available else LOCKED_COLOR


## Shows building `shown`: what it costs next to what the hold has. `blueprint`: whether the
## player has its blueprint; `locked`: whether a mission is underway; `can_build`: whether it can
## be built right now.
func show_build(
	shown: WeaponType,
	hold: Dictionary[OreType, float] = {},
	blueprint: bool = false,
	locked: bool = false,
	can_build: bool = false
) -> void:
	upgrade = null
	weapon_type = shown
	picking = false
	visible = shown != null
	if not shown:
		return
	_cost_row.visible = true
	_title.text = "%s — %s" % [shown.display_name, tr(shown.class_word)]
	_description.text = tr(shown.description)
	_pips.visible = false
	_effect.text = tr("Blueprint") if blueprint else tr("Locked")
	_cost.show_cost(shown.build_cost, hold)
	_status.visible = locked or not blueprint
	if locked:
		_status.text = tr("Locked until everyone is back aboard.")
	elif not blueprint:
		_status.text = tr("Building it needs its blueprint.")
	_buy.text = tr("Build")
	_buy.disabled = not can_build
	for dimmed: CanvasItem in [_title, _description, _cost_row]:
		dimmed.modulate = Color.WHITE if blueprint else LOCKED_COLOR


## Shows `shown`, selected on the rack: what it is (`owned`: whether the player has it, else
## "Locked") and "Lay on the bench".
func show_pick(shown: WeaponType, owned: bool = true) -> void:
	upgrade = null
	weapon_type = shown
	picking = true
	visible = shown != null
	if not shown:
		return
	_title.text = "%s — %s" % [shown.display_name, tr(shown.class_word)]
	_description.text = tr(shown.description)
	_pips.visible = false
	_effect.text = "" if owned else tr("Locked")
	_cost_row.visible = false
	_status.visible = false
	_buy.text = tr("Lay on the bench")
	_buy.disabled = false
	for dimmed: CanvasItem in [_title, _description]:
		dimmed.modulate = Color.WHITE if owned else LOCKED_COLOR


func press_primary() -> bool:
	if weapon_type and picking:
		var bench := station as WeaponStation
		if not bench:
			return false
		bench.lay_on_bench(weapon_type)
		return true
	if weapon_type:
		var weapon_station := station as WeaponStation
		return weapon_station != null and weapon_station.build(weapon_type)
	var upgrade_station := station as UpgradeStation
	return upgrade_station != null and upgrade_station.buy(upgrade)


## The buy button (for tests and probes).
func get_buy_button() -> Button:
	return _buy


## The line saying why nothing can be bought (for tests).
func get_status() -> Label:
	return _status


## Shows level `mk` of `max_mk` as pips in `row` (also a skill's ranks); those above `cap` are
## faint.
static func show_pips(row: HBoxContainer, mk: int, max_mk: int, cap: int = 99) -> void:
	while row.get_child_count() < max_mk:
		var pip := ColorRect.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pip)
	while row.get_child_count() > max_mk:
		var last: Node = row.get_child(-1)
		row.remove_child(last)
		last.queue_free()
	for i: int in max_mk:
		var color: Color = PIP_DARK if i < cap else PIP_OUT_OF_REACH
		(row.get_child(i) as ColorRect).color = PIP_LIT if i < mk else color


func _on_close_pressed() -> void:
	if station:
		station.close()


static func _bonus(shown: Upgrade, mk: int) -> int:
	return roundi((shown.multiplier(mk) - 1.0) * 100.0)
