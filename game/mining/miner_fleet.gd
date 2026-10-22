class_name MinerFleet
extends Resource
## A player's miners (see GAME_DESIGN.md, Miners): up to `SLOTS` crafted ones (`miners`, by their
## cradle's number), each built in the miners' room and kept, and the ship's standard-issue ones.
## Every player starts with M-01. A run takes up to `PER_RUN` miners: the crafted ones going along
## and standard-issue ones filling up the rest (which one is placed where: `Miner.take_from`). A
## crafted miner still standing on the planet when the run ends is lost (`end_run`): its cradle
## empties and `lost_at` says where until it's built again. Standard-issue miners are never lost.
## Building one runs on the wall clock like an upgrade level (`start_build`), and so do its parts'
## levels (`CraftedMiner.upgrades`); `update` lets those done take effect (the ship's
## `ProgressClock` calls it while no mission is underway, the save on loading). Each player has
## their own, in their own save.

## Cradles in the miners' room.
const SLOTS: int = 6
## Miners a player takes into a run.
const PER_RUN: int = 6

## The crafted miners by their cradle's number (built or under way); empty cradles are missing.
var miners: Dictionary[int, CraftedMiner] = {}
## Where each lost miner was left (e.g. "Torvane, Redscar Flats"), by its cradle's number, until
## it's built again.
var lost_at: Dictionary[int, String] = {}
## Standard-issue miners standing on the planet right now.
var standard_out: int = 0


func _init() -> void:
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


## The built crafted miners going along on the next run, by number.
func along() -> Array[CraftedMiner]:
	var result: Array[CraftedMiner] = []
	for number: int in range(1, SLOTS + 1):
		var miner: CraftedMiner = get_miner(number)
		if miner and miner.is_built() and miner.going_along:
			result.append(miner)
	return result


## How many standard-issue miners fill up a run.
func standard_count() -> int:
	return maxi(PER_RUN - along().size(), 0)


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


## Starts building a miner in the empty cradle `number` at `now` (Unix seconds), taking `seconds`;
## the build keeps `paid` (what stopping it gives back). Returns whether it started. Paying for it
## is up to the caller (see `PlayerHold.pay`).
func start_build(
	number: int, now: float, seconds: float, paid: Dictionary[ItemType, int] = {}
) -> bool:
	if not is_empty(number):
		return false
	put(CraftedMiner.new(number, TimedJob.new(1, now, seconds, paid)))
	return true


## Stops building the miner in cradle `number`. Returns whether one was under way (the caller
## gives its cost back).
func stop_build(number: int) -> bool:
	var miner: CraftedMiner = get_miner(number)
	if not miner or miner.is_built():
		return false
	_remove(number)
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


## Builds a miner in every empty cradle at once, at MK1 (the debug overlay).
func build_all() -> void:
	for number: int in range(1, SLOTS + 1):
		if is_empty(number):
			put(CraftedMiner.new(number))


func _remove(number: int) -> void:
	var miner: CraftedMiner = get_miner(number)
	if miner:
		miner.changed.disconnect(emit_changed)
	miners.erase(number)
