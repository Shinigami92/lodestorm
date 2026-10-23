class_name UpgradeCard
extends StationCard
## The holo card of an `UpgradeStation`: the selected upgrade's name and what it improves, its MK
## level as pips (like the pips on the weapons and the helmet), how much the next level improves
## (compared to MK1), the next level's cost per ore next to what the hold has of it (red where it's
## short), and "Upgrade". A level under way fills its pip, says the time left and offers "Stop"
## (pressed twice, the whole cost back). A drill says up to which ores it mines at full speed and
## which ores its next level adds (only ores found so far). A weapon's upgrade the player can't buy
## yet says "Locked", levels beyond the ship's reach show as faint pips and the card says which heat
## shield plate brings the next one, and while a mission is underway it says why nothing can be
## bought. A weapon's part is titled with the weapon's name. On the workbench, a weapon the player
## doesn't own shows what building it costs and "Build" (with its blueprint, see
## `WeaponStation.build`); a weapon selected on the rack shows what it is and "Lay on the bench".

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
@onready var _cost: ItemCost = %Cost
@onready var _cost_row: HFlowContainer = %CostRow
@onready var _time: Label = %Time
@onready var _reach: VBoxContainer = %Reach
@onready var _reach_label: Label = %ReachLabel
@onready var _reach_ores: HFlowContainer = %ReachOres
@onready var _reach_next: HFlowContainer = %ReachNext
@onready var _reach_next_label: Label = %ReachNextLabel
@onready var _reach_next_ores: HFlowContainer = %ReachNextOres
@onready var _status: Label = %Status
@onready var _buy: Button = %Buy
@onready var _close: Button = %Close


func _ready() -> void:
	_buy.pressed.connect(press_primary)
	_close.pressed.connect(_on_close_pressed)


func show_part(part: StationPart) -> void:
	var upgrade_station := station as UpgradeStation
	var hold: Dictionary[ItemType, float] = {}
	if upgrade_station and upgrade_station.user:
		hold = upgrade_station.user.hold.items
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
	var bought: Upgrades = upgrade_station.get_levels() if upgrade_station else null
	if not shown or not bought:
		show_upgrade(null)
		return
	var weapon: WeaponType = upgrade_station.get_weapon(shown)
	var job: TimedJob = bought.get_job(shown)
	var found: Dictionary[ItemType, bool] = {}
	if upgrade_station.user:
		found = upgrade_station.user.hold.found
	# The button keeps its state while a level runs: switching it off and on again every frame
	# would drop a mouse click on it.
	show_upgrade(
		shown,
		bought.mk(shown),
		hold,
		upgrade_station.is_available(shown),
		upgrade_station.is_locked(),
		upgrade_station.can_stop(shown) if job else upgrade_station.can_buy(shown),
		upgrade_station.upgrade_cap(),
		weapon.display_name if weapon else ""
	)
	show_reach(shown, bought.mk(shown), found)
	if job:
		show_job(
			job,
			Time.get_unix_time_from_system(),
			upgrade_station.can_stop(shown),
			upgrade_station.stop_press.is_armed(shown),
			upgrade_station.is_locked()
		)


## Shows `shown` at MK `mk` (null: nothing). `hold`: what the hold has; `available`: whether the
## player has its weapon; `locked`: whether a mission is underway; `can_buy`: whether its next
## level can be bought right now; `cap`: the highest MK level the ship's heat shield allows;
## `weapon_name`: the name of the weapon it's a part of (empty: none).
func show_upgrade(
	shown: Upgrade,
	mk: int = 1,
	hold: Dictionary[ItemType, float] = {},
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
	hide_reach()
	if not shown:
		return
	_cost_row.visible = true
	_title.text = tr(shown.display_name)
	if weapon_name:
		_title.text = "%s · %s" % [weapon_name, _title.text]
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
	# Only what can be started says how long it takes (the card keeps its height).
	_time.visible = next != null and available and not _status.visible
	if next:
		_time.text = tr("Takes %s") % FurnaceCard.duration_text(next.seconds)
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


## Shows a drill's reach at MK `mk` (after `show_upgrade`; other upgrades show none): the hardest
## ores it mines at full speed and those its next level adds, of the ores in `found`.
func show_reach(shown: Upgrade, mk: int, found: Dictionary[ItemType, bool]) -> void:
	if shown.hardness < 0:
		return
	var known: Array[OreType] = []
	for ore_type: OreType in OreCatalog.all().ores:
		if found.has(ore_type):
			known.append(ore_type)
	var hardness: int = shown.hardness_at(mk)
	# The hardest found ores it covers.
	var top: int = -1
	for ore_type: OreType in known:
		if ore_type.hardness <= hardness:
			top = maxi(top, ore_type.hardness)
	var next_hardness: int = shown.hardness_at(mk + 1) if mk < shown.max_mk() else hardness
	var covered: Array[OreType] = []
	var added: Array[OreType] = []
	for ore_type: OreType in known:
		if ore_type.hardness == top:
			covered.append(ore_type)
		elif ore_type.hardness > hardness and ore_type.hardness <= next_hardness:
			added.append(ore_type)
	_reach.visible = not covered.is_empty()
	_reach_label.text = tr("Full speed up to:")
	_show_ores(_reach_ores, covered)
	_reach_next.visible = next_hardness > hardness
	_reach_next_label.text = (
		tr("MK%d also:") % (mk + 1)
		if not added.is_empty()
		else tr("MK%d mines harder ores too.") % (mk + 1)
	)
	_show_ores(_reach_next_ores, added)


## Hides a drill's reach (see `show_reach`).
func hide_reach() -> void:
	_reach.visible = false
	_reach_next.visible = false


## Shows the level `job` under way (after `show_upgrade`) at `now` (Unix seconds): its pip
## filling, the time left and "Stop" (`can_stop`: whether it can be stopped
## now; `armed`: whether "Stop" was pressed once; `locked`: whether a mission is underway).
func show_job(
	job: TimedJob, now: float, can_stop: bool = true, armed: bool = false, locked: bool = false
) -> void:
	show_pips(_pips, job.level - 1, _pips.get_child_count(), 99, job.progress(now))
	_effect.text = tr("MK%d under way") % job.level
	_cost_row.visible = false
	_time.visible = true
	_time.text = tr("Time left: %s") % FurnaceCard.duration_text(job.time_left(now))
	_status.visible = locked or armed
	if locked:
		_status.text = tr("Locked until everyone is back aboard.")
	elif armed:
		_status.text = tr("Stop? The whole cost goes back to the hold.")
	_buy.text = tr("Stop for sure") if armed else tr("Stop")
	_buy.disabled = not can_stop


## Shows building `shown`: what it costs next to what the hold has. `blueprint`: whether the
## player has its blueprint; `locked`: whether a mission is underway; `can_build`: whether it can
## be built right now.
func show_build(
	shown: WeaponType,
	hold: Dictionary[ItemType, float] = {},
	blueprint: bool = false,
	locked: bool = false,
	can_build: bool = false
) -> void:
	upgrade = null
	weapon_type = shown
	picking = false
	visible = shown != null
	hide_reach()
	if not shown:
		return
	_cost_row.visible = true
	_title.text = "%s · %s" % [shown.display_name, tr(shown.class_word)]
	_description.text = tr(shown.description)
	_pips.visible = false
	_time.visible = false
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
	hide_reach()
	if not shown:
		return
	_title.text = "%s · %s" % [shown.display_name, tr(shown.class_word)]
	_description.text = tr(shown.description)
	_pips.visible = false
	_effect.text = "" if owned else tr("Locked")
	_cost_row.visible = false
	_time.visible = false
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
	if not upgrade_station:
		return false
	var bought: Upgrades = upgrade_station.get_levels()
	if bought and bought.is_running(upgrade):
		return upgrade_station.stop(upgrade)
	return upgrade_station.buy(upgrade)


## The buy button (for tests and probes).
func get_buy_button() -> Button:
	return _buy


## The line saying how long the next level takes, or the time left of one under way (for tests).
func get_time() -> Label:
	return _time


## The line saying why nothing can be bought (for tests).
func get_status() -> Label:
	return _status


## Shows level `mk` of `max_mk` as pips in `row` (also a skill's ranks); those above `cap` are
## faint. With `progress` (0–1), the level after `mk` is under way: its pip fills from the left.
static func show_pips(
	row: HBoxContainer, mk: int, max_mk: int, cap: int = 99, progress: float = -1.0
) -> void:
	while row.get_child_count() < max_mk:
		var pip := ColorRect.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.color = PIP_LIT
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_child(fill)
		row.add_child(pip)
	while row.get_child_count() > max_mk:
		var last: Node = row.get_child(-1)
		row.remove_child(last)
		last.queue_free()
	for i: int in max_mk:
		var color: Color = PIP_DARK if i < cap else PIP_OUT_OF_REACH
		var pip := row.get_child(i) as ColorRect
		pip.color = PIP_LIT if i < mk else color
		var fill := pip.get_node(^"Fill") as ColorRect
		fill.visible = i == mk and progress >= 0.0
		fill.size = Vector2(PIP_SIZE.x * clampf(progress, 0.0, 1.0), PIP_SIZE.y)


func _on_close_pressed() -> void:
	if station:
		station.close()


## Shows the badges of `ores` in `row` (made again only when they change).
static func _show_ores(row: HFlowContainer, ores: Array[OreType]) -> void:
	var shown: Array[OreType] = []
	for badge: Node in row.get_children():
		shown.append((badge as ItemBadge).item as OreType)
	if shown == ores:
		return
	for node: Node in row.get_children():
		row.remove_child(node)
		node.queue_free()
	for ore_type: OreType in ores:
		row.add_child(ItemBadge.new(ore_type))


static func _bonus(shown: Upgrade, mk: int) -> int:
	return roundi((shown.multiplier(mk) - 1.0) * 100.0)
