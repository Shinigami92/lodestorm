class_name HeatShieldCard
extends StationCard
## The holo card of the drive core (`HeatShieldStation`): the selected plate's MK level and the
## bodies it opens, then by its state: installed; the next one with its cost per ore (paid so far
## of the cost, and what the hold has, red where the hold can't cover the rest), whether it's the
## ship's project, "Pay the rest from the hold" and "Make it the ship's project"; a later one with
## its cost and the level it needs first. While a mission is underway it says why nothing can be
## done, and to a guest that only the host can.

const INSTALLED_COLOR := Color(1.0, 0.62, 0.25)

## The plate shown (its MK level), 0 for none.
var mk: int = 0

## The cost shown, so the rows are only rebuilt when it changes.
var _cost: Dictionary[OreType, int] = {}
var _paid_labels: Dictionary[OreType, Label] = {}
var _hold_labels: Dictionary[OreType, Label] = {}

@onready var _title: Label = %Title
@onready var _opens: Label = %Opens
@onready var _state: Label = %State
@onready var _cost_grid: GridContainer = %CostGrid
@onready var _status: Label = %Status
@onready var _pay: Button = %Pay
@onready var _project: Button = %Project


func _ready() -> void:
	_pay.pressed.connect(_on_pay_pressed)
	_project.pressed.connect(_on_project_pressed)


func show_part(part: StationPart) -> void:
	var shield_station := station as HeatShieldStation
	var shield: HeatShield = shield_station.get_heat_shield() if shield_station else null
	var level: int = shield_station.level_of(part) if shield_station else 0
	if not shield or level < 2:
		show_plate(null, 0)
		return
	var hold: Dictionary[ItemType, float] = {}
	if shield_station.user:
		hold = shield_station.user.hold.items
	show_plate(
		shield,
		level,
		shield_station.opened_by(level),
		hold,
		shield_station.is_locked(),
		shield_station.is_host()
	)


## Shows plate MK `level` of `shield` (null: nothing). `opens`: the names of the bodies it opens;
## `hold`: what the hold has; `locked`: whether a mission is underway; `host`: whether the player
## using it is the host.
func show_plate(
	shield: HeatShield,
	level: int,
	opens: PackedStringArray = [],
	hold: Dictionary[ItemType, float] = {},
	locked: bool = false,
	host: bool = true
) -> void:
	mk = level
	visible = shield != null and level >= 2
	if not visible:
		return
	var plate: ShieldPlate = shield.plate_for(level)
	var installed: bool = level <= shield.mk
	var is_next: bool = level == shield.mk + 1
	_title.text = tr("Heat shield MK%d") % level
	_opens.text = tr("Opens %s") % ", ".join(opens)
	_state.visible = not is_next
	if installed:
		_state.text = tr("Installed")
		_state.add_theme_color_override(&"font_color", INSTALLED_COLOR)
	else:
		_state.text = tr("Needs MK%d first.") % (level - 1)
		_state.remove_theme_color_override(&"font_color")
	_cost_grid.visible = not installed
	if not installed:
		var paid: Dictionary[OreType, float] = {}
		if is_next:
			paid = shield.paid
		_show_cost(plate.cost, paid, hold)
		dim([_cost_grid], not is_next)
	var status: String = ""
	if is_next and locked:
		status = _locked_text()
	elif is_next and not host:
		status = tr("Only the host can change the ship's project.")
	elif is_next and shield.project:
		status = tr("The ship's project: every run pays into it first.")
	_status.text = status
	_status.visible = status != ""
	_pay.visible = is_next
	# Once it is the project, the status line says so.
	_project.visible = is_next and not shield.project
	_pay.text = tr("Pay the rest from the hold")
	_project.text = tr("Make it the ship's project")
	var usable: bool = is_next and not locked and host
	_pay.disabled = not usable or not _hold_covers_any(shield.missing(), hold)
	_project.disabled = not usable or shield.project


## `interact`: makes the next plate the ship's project, or once it is, pays the rest from the
## hold.
func press_primary() -> bool:
	var shield_station := station as HeatShieldStation
	if not shield_station or mk < 2:
		return false
	return shield_station.set_project(mk) or shield_station.pay(mk)


## The buttons (for tests and probes).
func get_pay_button() -> Button:
	return _pay


func get_project_button() -> Button:
	return _project


## Per ore of `cost`: its badge, "paid / cost" and what the hold has (red where it can't cover
## the rest).
func _show_cost(
	cost: Dictionary[OreType, int],
	paid: Dictionary[OreType, float],
	hold: Dictionary[ItemType, float]
) -> void:
	if cost != _cost:
		_cost = cost.duplicate()
		for node: Node in _cost_grid.get_children():
			if not node.is_in_group(&"cost_header"):
				node.free()
		_paid_labels.clear()
		_hold_labels.clear()
		for ore_type: OreType in cost:
			_cost_grid.add_child(ItemBadge.new(ore_type))
			_paid_labels[ore_type] = _amount_label()
			_cost_grid.add_child(_paid_labels[ore_type])
			_hold_labels[ore_type] = _amount_label()
			_cost_grid.add_child(_hold_labels[ore_type])
	for ore_type: OreType in cost:
		var paid_so_far: float = paid.get(ore_type, 0.0)
		var in_hold: float = hold.get(ore_type, 0.0)
		_paid_labels[ore_type].text = "%d / %d" % [floori(paid_so_far), cost[ore_type]]
		var label: Label = _hold_labels[ore_type]
		label.text = "%d" % floori(in_hold)
		if in_hold < cost[ore_type] - paid_so_far - HeatShield.PAID_TOLERANCE:
			label.add_theme_color_override(&"font_color", CardPalette.WARNING)
		else:
			label.remove_theme_color_override(&"font_color")


func _amount_label() -> Label:
	var label := _label("")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## Whether the hold has anything of what's `missing`.
static func _hold_covers_any(
	missing: Dictionary[OreType, float], hold: Dictionary[ItemType, float]
) -> bool:
	for ore_type: OreType in missing:
		var in_hold: float = hold.get(ore_type, 0.0)
		if in_hold > 0.0:
			return true
	return false


func _on_pay_pressed() -> void:
	var shield_station := station as HeatShieldStation
	if shield_station:
		shield_station.pay(mk)


func _on_project_pressed() -> void:
	var shield_station := station as HeatShieldStation
	if shield_station:
		shield_station.set_project(mk)
