class_name MinerCard
extends UpgradeCard
## The holo card of the miners' bay (`MinerBayStation`): for a part on the pad like the upgrade
## card; for the miner on the pad its number, what keeps it, its parts' MK pips (a level under way
## filling its pip), how many standard-issue miners fill up the next run and "Leave aboard" /
## "Take along"; for an empty cradle what building a miner costs and takes (and where its last
## miner was lost) with "Build", for one being built the time left and "Stop" (pressed twice),
## for one the ship doesn't have that it was sold off.

## The crafted miner shown on the pad, or null.
var miner: CraftedMiner
## The cradle shown (its number; 0: none).
var cradle: int = 0

## Per part its name and its pips.
var _part_rows: Dictionary[Upgrade, HBoxContainer] = {}
var _parts := GridContainer.new()


func _ready() -> void:
	super()
	_parts.name = "Parts"
	_parts.columns = 2
	_parts.add_theme_constant_override(&"h_separation", 16)
	_parts.add_theme_constant_override(&"v_separation", 4)
	for part: Upgrade in CraftedMiner.PARTS:
		var label := Label.new()
		label.text = part.display_name
		label.theme_type_variation = &"CardText"
		_parts.add_child(label)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override(&"separation", 6)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_parts.add_child(pips)
		_part_rows[part] = pips
	var level: Node = _effect.get_parent()
	level.add_sibling(_parts)
	# Whether a miner goes along is a sentence, not a number.
	_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_parts.visible = false


func show_part(part: StationPart) -> void:
	var bay := station as MinerBayStation
	if not bay or not part or not (part == bay.get_miner_part() or part is MinerCradle):
		miner = null
		cradle = 0
		_parts.visible = false
		_buy.visible = true
		super(part)
		return
	var now: float = Time.get_unix_time_from_system()
	var fleet: MinerFleet = bay.get_fleet()
	if part == bay.get_miner_part():
		var shown: CraftedMiner = bay.pad_miner()
		show_miner(
			shown,
			bay.upgrade_cap(),
			fleet.standard_count() if fleet else 0,
			bay.is_locked(),
			now,
			shown != null and bay.can_toggle(shown.number)
		)
		return
	var number: int = (part as MinerCradle).number
	var building: CraftedMiner = fleet.get_miner(number) if fleet else null
	if building and not building.is_built():
		show_building(
			building,
			now,
			bay.can_stop_build(number),
			bay.stop_press.is_armed(building),
			bay.is_locked()
		)
		return
	if fleet and not building and not fleet.cradles.is_open(number):
		show_missing(number)
		return
	var hold: Dictionary[ItemType, float] = {}
	if bay.user:
		hold = bay.user.hold.items
	var lost_where: String = fleet.lost_at.get(number, "") if fleet else ""
	show_cradle(
		number,
		bay.settings.build_cost,
		hold,
		bay.settings.build_seconds,
		lost_where,
		bay.is_locked(),
		bay.can_build(number)
	)


## Shows `shown` on the pad (null: nothing): its parts' levels up to `cap` (the ship's reach),
## `standard` standard-issue miners filling up the next run; `locked`: whether a mission is
## underway; `can_toggle`: whether it can be left aboard or taken along now.
func show_miner(
	shown: CraftedMiner,
	cap: int = 99,
	standard: int = 0,
	locked: bool = false,
	now: float = 0.0,
	can_toggle: bool = true
) -> void:
	_reset(shown != null)
	miner = shown
	if not shown:
		return
	_title.text = shown.plate()
	_description.text = tr("Lost only if it's left on the planet.")
	_effect.text = (tr("Goes along next run") if shown.going_along else tr("Stays aboard next run"))
	_parts.visible = true
	for part: Upgrade in _part_rows:
		var job: TimedJob = shown.upgrades.get_job(part)
		var mk: int = job.level - 1 if job else shown.upgrades.mk(part)
		show_pips(_part_rows[part], mk, part.max_mk(), cap, job.progress(now) if job else -1.0)
	_time.visible = true
	_time.text = tr("Standard-issue miners: %d") % standard
	_status.visible = locked or (shown.is_upgrading() and shown.going_along)
	if locked:
		_status.text = tr("Locked until everyone is back aboard.")
	else:
		_status.text = tr("A level under way is lost with it.")
	_buy.text = tr("Leave aboard") if shown.going_along else tr("Take along")
	_buy.disabled = not can_toggle


## Shows the empty cradle `number`: building a miner costs `cost` (next to what `hold` has) and
## takes `seconds`; `lost_where`: where its last miner was lost (empty: none); `locked`: whether a
## mission is underway; `can_build`: whether it can be built right now.
func show_cradle(
	number: int,
	cost: Dictionary[ItemType, int],
	hold: Dictionary[ItemType, float] = {},
	seconds: float = 0.0,
	lost_where: String = "",
	locked: bool = false,
	can_build: bool = false
) -> void:
	_reset(true)
	cradle = number
	_title.text = CraftedMiner.plate_of(number)
	_description.text = (tr("Lost on %s.") % lost_where if lost_where else tr("An empty cradle."))
	_effect.text = tr("Build a miner")
	_cost_row.visible = true
	_cost.show_cost(cost, hold)
	_time.visible = not locked
	_time.text = tr("Takes %s") % FurnaceCard.duration_text(seconds)
	_status.visible = locked
	_status.text = tr("Locked until everyone is back aboard.")
	_buy.text = tr("Build")
	_buy.disabled = not can_build


## Shows the cradle `number` the ship doesn't have: sold off, nothing to build there.
func show_missing(number: int) -> void:
	_reset(true)
	cradle = number
	_title.text = CraftedMiner.plate_of(number)
	_description.text = tr(
		"This cradle was sold off before the ship was bought. Only its rails are left."
	)
	_effect.text = ""
	_buy.visible = false


## Shows `building` under way at `now` (Unix seconds): the time left and "Stop" (`can_stop`:
## whether it can be stopped now; `armed`: whether "Stop" was pressed once; `locked`: whether a
## mission is underway).
func show_building(
	building: CraftedMiner,
	now: float,
	can_stop: bool = true,
	armed: bool = false,
	locked: bool = false
) -> void:
	_reset(true)
	cradle = building.number
	_title.text = building.plate()
	_description.text = tr("Being built.")
	_effect.text = "%d %%" % roundi(building.build.progress(now) * 100.0)
	_time.visible = true
	_time.text = tr("Time left: %s") % FurnaceCard.duration_text(building.build.time_left(now))
	_status.visible = locked or armed
	if locked:
		_status.text = tr("Locked until everyone is back aboard.")
	elif armed:
		_status.text = tr("Stop? The whole cost goes back to the hold.")
	_buy.text = tr("Stop for sure") if armed else tr("Stop")
	_buy.disabled = not can_stop


func press_primary() -> bool:
	var bay := station as MinerBayStation
	if not bay or (not miner and cradle == 0):
		return super()
	if not _buy.visible:
		return false
	if miner:
		return bay.toggle_along(miner.number)
	var building: CraftedMiner = bay.get_fleet().get_miner(cradle) if bay.get_fleet() else null
	if building and not building.is_built():
		return bay.stop_build(cradle)
	return bay.build(cradle)


## Clears what the upgrade card shows, for the miner's and the cradle's lines.
func _reset(shown: bool) -> void:
	upgrade = null
	weapon_type = null
	picking = false
	miner = null
	cradle = 0
	visible = shown
	_buy.visible = true
	_pips.visible = false
	_parts.visible = false
	_cost_row.visible = false
	_time.visible = false
	_status.visible = false
	hide_reach()
	for dimmed: CanvasItem in [_title, _description, _pips, _cost_row]:
		dimmed.modulate = Color.WHITE
