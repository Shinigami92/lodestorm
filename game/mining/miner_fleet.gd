class_name MinerFleet
extends Resource
## A player's miners (see docs/design/mining.md): up to `SLOTS` crafted ones (`miners`, by their
## cradle's number), each built in the miners' room and kept, and the ship's standard-issue ones.
## Every player starts with M-01. How many cradles are open is the ship's (`cradles`): a crafted
## miner is built only in an open one, and a run takes as many miners as there are open cradles,
## the crafted ones going along first (by number, the others stay aboard) and standard-issue ones
## filling up the rest (which one is placed where: `Miner.take_from`). A
## crafted miner still standing on the planet when the run ends is lost (`end_run`): its cradle
## empties and `lost_at` says where until it's built again. Standard-issue miners are never lost.
## Building one runs on the wall clock like an upgrade level (`start_build`), and so do its parts'
## levels (`CraftedMiner.upgrades`); `update` lets those done take effect (the ship's
## `ProgressClock` calls it while no mission is underway, the save on loading). Each player has
## their own, in their own save.

## Cradles in the miners' room.
const SLOTS: int = 6

## The crafted miners by their cradle's number (built or under way); empty cradles are missing.
var miners: Dictionary[int, CraftedMiner] = {}
## Where each lost miner was left (e.g. "Torvane, Redscar Flats"), by its cradle's number, until
## it's built again.
var lost_at: Dictionary[int, String] = {}
## Standard-issue miners standing on the planet right now.
var standard_out: int = 0
## The ship's open cradles (the player's ship links its own, see `Player`).
var cradles: Cradles:
	set(value):
		if cradles:
			cradles.changed.disconnect(emit_changed)
		cradles = value
		cradles.changed.connect(emit_changed)
		emit_changed()


func _init() -> void:
	cradles = Cradles.new()
	put(CraftedMiner.new(1))


## The crafted miner in cradle `number`, or null.
func get_miner(number: int) -> CraftedMiner:
	return miners.get(number, null)


## Puts `miner` into its cradle (a new one, a saved one), replacing what's there.
func put(miner: CraftedMiner) -> void:
	var old: CraftedMiner = get_miner(miner.number)
	if old:
		old.changed.disconnect(emit_changed)
	miners[miner.number] = miner
	miner.changed.connect(emit_changed)
	lost_at.erase(miner.number)
	emit_changed()


## Empties every cradle (before a save is read).
func clear() -> void:
	for number: int in miners.keys():
		_remove(number)
	lost_at.clear()
	standard_out = 0
	emit_changed()


## How many miners a run takes: one per open cradle.
func per_run() -> int:
	return cradles.open


## The built crafted miners going along on the next run, by number, at most `per_run`.
func along() -> Array[CraftedMiner]:
	var result: Array[CraftedMiner] = []
	for number: int in range(1, SLOTS + 1):
		var miner: CraftedMiner = get_miner(number)
		if miner and miner.is_built() and miner.going_along and result.size() < per_run():
			result.append(miner)
	return result


## How many standard-issue miners fill up a run.
func standard_count() -> int:
	return maxi(per_run() - along().size(), 0)


## How many miners are left to place in this run.
func left_to_place() -> int:
	return waiting().size() + standard_left()


## The crafted miners going along that are still to place in this run, by number.
func waiting() -> Array[CraftedMiner]:
	var result: Array[CraftedMiner] = []
	for miner: CraftedMiner in along():
		if not miner.out:
			result.append(miner)
	return result


## How many standard-issue miners are still to place in this run.
func standard_left() -> int:
	return maxi(standard_count() - standard_out, 0)


## Takes a miner out to place it: `miner` (one of `waiting`, marked `out`), or a standard-issue one
## for null. Check `left_to_place` first.
func take(miner: CraftedMiner) -> void:
	if miner:
		miner.out = true
	else:
		standard_out += 1
	emit_changed()


## Brings a miner picked up back (`miner`, or null for a standard-issue one), to place it again.
func bring_back(miner: CraftedMiner) -> void:
	if miner:
		miner.out = false
	else:
		standard_out = maxi(standard_out - 1, 0)
	emit_changed()


## Ends the run: every crafted miner still standing on the planet is lost (left at `where`), with
## the level under way of its parts; standard-issue ones are back for the next run. Returns the
## lost miners' numbers.
func end_run(where: String) -> Array[int]:
	var lost: Array[int] = []
	for number: int in miners.keys():
		var miner: CraftedMiner = miners[number]
		miner.health = -1.0
		if miner.out:
			lost.append(number)
			miner.out = false
	for number: int in lost:
		_remove(number)
		lost_at[number] = where
	standard_out = 0
	emit_changed()
	return lost


## Whether cradle `number` is empty (no miner built or under way).
func is_empty(number: int) -> bool:
	return number >= 1 and number <= SLOTS and not miners.has(number)


## Starts building a miner in the empty open cradle `number` at `now` (Unix seconds), taking
## `settings.build_seconds`, its `build_cost` paid from `hold` (the build keeps what was paid).
## Returns whether it started.
func start_build(number: int, settings: MinerSettings, hold: PlayerHold, now: float) -> bool:
	if not is_empty(number) or not cradles.is_open(number) or not hold.pay(settings.build_cost):
		return false
	put(CraftedMiner.new(number, TimedJob.new(1, now, settings.build_seconds, settings.build_cost)))
	return true


## Stops building the miner in cradle `number`, what was paid for it back into `hold`. Returns
## whether one was under way.
func stop_build(number: int, hold: PlayerHold) -> bool:
	var miner: CraftedMiner = get_miner(number)
	if not miner or miner.is_built():
		return false
	_remove(number)
	hold.refund(miner.build.paid)
	emit_changed()
	return true


## Lets every build and part level done by `now` (Unix seconds) take effect. Returns what finished:
## the miners built and the upgrades whose level is done.
func update(now: float) -> Array[Resource]:
	var done: Array[Resource] = []
	for miner: CraftedMiner in miners.values():
		if miner.build and miner.build.is_done(now):
			miner.build = null
			done.append(miner)
			miner.emit_changed()
		done.append_array(miner.upgrades.update(now))
	return done


## Lets every build and part level under way take effect right now (the debug overlay).
func finish_all() -> Array[Resource]:
	var done: Array[Resource] = []
	for miner: CraftedMiner in miners.values():
		if miner.build:
			miner.build = null
			done.append(miner)
			miner.emit_changed()
		done.append_array(miner.upgrades.finish_all())
	return done


## Builds a miner in every empty open cradle at once, at MK1 (the debug overlay).
func build_all() -> void:
	for number: int in range(1, cradles.open + 1):
		if is_empty(number):
			put(CraftedMiner.new(number))


## What's saved: the crafted miners (`CraftedMiner.save_data`) and where the lost ones were left,
## by their number (as a string, like every JSON key).
func save_data() -> Dictionary:
	var saved_miners: Array = []
	for number: int in range(1, SLOTS + 1):
		if miners.has(number):
			saved_miners.append(miners[number].save_data())
	var saved_lost: Dictionary = {}
	for number: int in lost_at:
		saved_lost[str(number)] = lost_at[number]
	return {"miners": saved_miners, "lost": saved_lost}


## Reads what a save has (`save_data`) in place of the miners there are; the builds and levels
## done since take effect with `update`. Returns whether all of it read.
func load_data(saved: Variant) -> bool:
	if saved == null:
		return true
	var data: Dictionary = saved if saved is Dictionary else {}
	var saved_miners: Variant = data.get("miners", [])
	var saved_lost: Variant = data.get("lost", {})
	if not saved is Dictionary or not saved_miners is Array or not saved_lost is Dictionary:
		return SaveData.skipped("miners", saved)
	clear()
	var complete: bool = true
	for entry: Variant in saved_miners as Array:
		var miner: CraftedMiner = CraftedMiner.from_data(entry)
		if miner and is_empty(miner.number):
			complete = miner.load_data(entry as Dictionary) and complete
			put(miner)
		else:
			complete = SaveData.skipped("miner", entry)
	var lost: Dictionary = saved_lost
	for key: Variant in lost:
		var number: int = (key as String).to_int() if key is String else 0
		if is_empty(number) and lost[key] is String:
			lost_at[number] = lost[key]
		else:
			complete = SaveData.skipped("lost miner", key)
	emit_changed()
	return complete


func _remove(number: int) -> void:
	var miner: CraftedMiner = get_miner(number)
	if miner:
		miner.changed.disconnect(emit_changed)
	miners.erase(number)
