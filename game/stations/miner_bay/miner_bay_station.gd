class_name MinerBayStation
extends UpgradeStation
## The miners' room's station (see GAME_DESIGN.md, Miners): the bay with a cradle per crafted miner
## along the back wall (`MinerCradle`, three on each side of the door, M-01 on the left) and the
## maintenance pad in front of them. Picking a built miner in its cradle (a click, the directions,
## or `tab_prev`/`tab_next` through the cradles) puts it on the pad (its cradle shows empty
## meanwhile), where its parts are the upgrades (drill, ore tank, hose reel, plating; bought into
## the miner's own levels, `get_levels`) and the pad's `Miner` part is the miner itself (its card:
## its number, its parts' MK pips, whether it goes along on the next run, `toggle_along`). An empty
## cradle builds a miner (`build`, for `settings.build_cost`, on the wall clock), one under way can
## be stopped for the whole cost back (pressed twice). It shows the miners of the player using it,
## else of the first local player. Like the other stations, nothing can be bought, built, stopped
## or toggled while a mission is underway.

## The cradles' positions along the back wall, from the `Cradles` node (M-01 first).
const CRADLE_SPOTS: Array[float] = [-4.8, -3.55, -2.3, 2.3, 3.55, 4.8]
## How far towards the camera a cradle's card floats from the cradle, in m: as near as the pad's,
## so it reads as big, and below the row on the screen, so it hides no other cradle.
const CRADLE_CARD_DISTANCE: float = 4.0
## How far below the cradle (on the screen) its card floats, in m.
const CRADLE_CARD_DROP: float = 1.9

## The build cost and time.
@export var settings: MinerSettings
## The miner model stowed in the cradles.
@export var model_scene: PackedScene

## The number of the miner on the pad (0: none).
var pad_number: int = 0

var _cradles: Array[MinerCradle] = []

@onready var _model: Node3D = $Model
@onready var _miner_part: StationPart = $Miner
@onready var _pad_plate: Label3D = $PadPlate
@onready var _cradle_row: Node3D = $Cradles


func _ready() -> void:
	super()
	for number: int in range(1, MinerFleet.SLOTS + 1):
		var cradle := MinerCradle.new()
		cradle.setup(number, model_scene)
		cradle.position.x = CRADLE_SPOTS[number - 1]
		_cradle_row.add_child(cradle)
		_cradles.append(cradle)
	_show_fleet()


func _process(delta: float) -> void:
	super(delta)
	_show_fleet()


## The player whose miners it shows: the one using it, else the first local one (or null).
func viewer() -> Player:
	return user if user else Player.first_local(get_tree())


## The fleet it shows, or null.
func get_fleet() -> MinerFleet:
	var player: Player = viewer()
	return player.fleet if player else null


## The crafted miner on the pad, or null.
func pad_miner() -> CraftedMiner:
	var fleet: MinerFleet = get_fleet()
	return fleet.get_miner(pad_number) if fleet and pad_number > 0 else null


## The cradle of miner `number`, or null.
func get_cradle(number: int) -> MinerCradle:
	return _cradles[number - 1] if number >= 1 and number <= _cradles.size() else null


## The pad's part standing for the whole miner on it.
func get_miner_part() -> StationPart:
	return _miner_part


## The cradles' parts selectable right now (not the one whose miner is on the pad), by number.
func get_cradle_parts() -> Array[StationPart]:
	var parts: Array[StationPart] = []
	for cradle: MinerCradle in _cradles:
		if cradle.number != pad_number:
			parts.append(cradle)
	return parts


func get_parts() -> Array[StationPart]:
	var parts: Array[StationPart] = super()
	parts = parts.filter(func(part: StationPart) -> bool: return not part is MinerCradle)
	parts.append_array(get_cradle_parts())
	return parts


func get_levels() -> Upgrades:
	var miner: CraftedMiner = pad_miner()
	return miner.upgrades if user and miner and miner.is_built() else null


## Whether the miner on the pad is built (its parts can be upgraded).
func is_available(_upgrade: Upgrade) -> bool:
	var miner: CraftedMiner = pad_miner()
	return miner != null and miner.is_built()


## Puts the built miner `number` on the pad. Returns whether it did.
func put_on_pad(number: int) -> bool:
	var fleet: MinerFleet = get_fleet()
	var miner: CraftedMiner = fleet.get_miner(number) if fleet else null
	if not miner or not miner.is_built():
		return false
	if number != pad_number:
		stop_press.reset()
	pad_number = number
	_show_fleet()
	return true


## A cradle with a built miner puts it on the pad and selects the pad's miner instead.
func select(part: StationPart) -> void:
	var cradle := part as MinerCradle
	if cradle and put_on_pad(cradle.number):
		part = _miner_part
	super(part)


## Whether the player using it can build a miner in cradle `number` right now: it's empty, the hold
## has the cost and no mission is underway.
func can_build(number: int) -> bool:
	return (
		not is_locked()
		and user != null
		and user.fleet.is_empty(number)
		and user.hold.can_pay(settings.build_cost)
	)


## Builds a miner in cradle `number` for the player using it, paid from the hold, on the wall clock.
## Returns whether it started.
func build(number: int) -> bool:
	if not can_build(number) or not user.hold.pay(settings.build_cost):
		return false
	var now: float = Time.get_unix_time_from_system()
	user.fleet.start_build(number, now, settings.build_seconds, settings.build_cost)
	refresh()
	return true


## Whether the miner being built in cradle `number` can be stopped now.
func can_stop_build(number: int) -> bool:
	if is_locked() or not user:
		return false
	var miner: CraftedMiner = user.fleet.get_miner(number)
	return miner != null and not miner.is_built()


## Stops building the miner in cradle `number` on the second press (`stop_press`), what was paid
## for it back into the hold. Returns whether it stopped.
func stop_build(number: int) -> bool:
	if not can_stop_build(number):
		return false
	if not stop_press.press(user.fleet.get_miner(number)):
		refresh()
		return false
	var paid: Dictionary[ItemType, int] = user.fleet.get_miner(number).build.paid
	user.fleet.stop_build(number)
	user.hold.refund(paid)
	refresh()
	return true


## Whether the player using it can switch whether miner `number` goes along now.
func can_toggle(number: int) -> bool:
	if is_locked() or not user:
		return false
	var miner: CraftedMiner = user.fleet.get_miner(number)
	return miner != null and miner.is_built()


## Switches whether the user's miner `number` goes along on the next run. Returns whether it did.
func toggle_along(number: int) -> bool:
	if not can_toggle(number):
		return false
	var miner: CraftedMiner = user.fleet.get_miner(number)
	miner.going_along = not miner.going_along
	miner.emit_changed()
	refresh()
	return true


## Its miners' parts and the miners built here.
func sells(item: Resource) -> bool:
	return item is CraftedMiner or item in CraftedMiner.PARTS


## `tab_prev`/`tab_next`: the previous or next cradle (its miner onto the pad, if built).
func _cycle(step_by: int) -> void:
	var current: int = pad_number
	var cradle := selected as MinerCradle
	if cradle:
		current = cradle.number
	var next: int = posmod(maxi(current, 1) - 1 + step_by, MinerFleet.SLOTS) + 1
	select(get_cradle(next))


func _card_position(camera: Camera3D) -> Vector3:
	if not selected is MinerCradle:
		return super(camera)
	var view: Basis = camera.global_basis
	return selected.global_position + view.z * CRADLE_CARD_DISTANCE - view.y * CRADLE_CARD_DROP


func _opened() -> void:
	_show_fleet()
	if not selected:
		var miner: CraftedMiner = pad_miner()
		if miner and miner.is_built():
			select(_miner_part)
		else:
			select(get_cradle(1))
	super()


## Shows the viewer's miners: each cradle's look, the miner on the pad (the first built one when
## the one there is gone) and its plate.
func _show_fleet() -> void:
	var fleet: MinerFleet = get_fleet()
	var miner: CraftedMiner = pad_miner()
	if fleet and not (miner and miner.is_built()):
		pad_number = 0
		for number: int in range(1, MinerFleet.SLOTS + 1):
			var candidate: CraftedMiner = fleet.get_miner(number)
			if candidate and candidate.is_built():
				pad_number = number
				break
	var on_pad: bool = pad_number > 0
	_model.visible = on_pad
	_pad_plate.visible = on_pad
	_pad_plate.text = CraftedMiner.plate_of(pad_number) if on_pad else ""
	for part: Node in [_miner_part, $Drill, $Tank, $Hose, $Plating]:
		(part as Node3D).visible = on_pad
	var now: float = Time.get_unix_time_from_system()
	for cradle: MinerCradle in _cradles:
		var crafted: CraftedMiner = fleet.get_miner(cradle.number) if fleet else null
		if crafted and cradle.number == pad_number:
			cradle.show_look(MinerCradle.Look.ON_PAD)
		elif crafted and crafted.is_built():
			cradle.show_look(MinerCradle.Look.BUILT)
		elif crafted:
			cradle.show_look(MinerCradle.Look.BUILDING, crafted.build.progress(now))
		else:
			cradle.show_look(MinerCradle.Look.EMPTY)
	if not user:
		return
	# A miner built meanwhile goes onto the pad; with none left there, the first cradle.
	if selected is MinerCradle:
		var picked: CraftedMiner = fleet.get_miner((selected as MinerCradle).number)
		if picked and picked.is_built():
			select(selected)
	elif selected and not selected.is_visible_in_tree():
		select(get_cradle(1))
