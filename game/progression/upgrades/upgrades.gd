class_name Upgrades
extends Resource
## The MK levels a player bought at the upgrade stations, per upgrade; everything else is MK1.
## Each player has their own (like their `Arsenal`). A level bought runs on the wall clock first
## (`jobs`, see `TimedJob`): one level per upgrade at a time, any number of upgrades at once; it
## takes effect when `update` finds it done (the ship's `ProgressClock` calls it while no mission
## is underway, the save on loading).

## Emitted when the level under way of `upgrade` is done and taken effect.
signal finished(upgrade: Upgrade)

## MK level per upgrade, only those above MK1.
@export var levels: Dictionary[Upgrade, int] = {}

## The level under way per upgrade.
var jobs: Dictionary[Upgrade, TimedJob] = {}


## The MK level of `upgrade` (1 when it's not bought yet or null).
func mk(upgrade: Upgrade) -> int:
	if not upgrade:
		return 1
	var level: int = levels.get(upgrade, 1)
	return level


## How much `upgrade` improves its values right now (1 at MK1 or for null).
func multiplier(upgrade: Upgrade) -> float:
	return upgrade.multiplier(mk(upgrade)) if upgrade else 1.0


## The level to buy next for `upgrade`, or null when it's at its highest.
func next_level(upgrade: Upgrade) -> UpgradeLevel:
	return upgrade.level_after(mk(upgrade)) if upgrade else null


## What the next level of `upgrade` costs, in units per item (empty when it's at its highest or
## null).
func next_cost(upgrade: Upgrade) -> Dictionary[ItemType, int]:
	return upgrade.cost_of(mk(upgrade) + 1) if upgrade else {}


## The level of `upgrade` under way, or null.
func get_job(upgrade: Upgrade) -> TimedJob:
	return jobs.get(upgrade, null)


## Whether a level of `upgrade` is under way.
func is_running(upgrade: Upgrade) -> bool:
	return jobs.has(upgrade)


## Starts the next level of `upgrade` at `now` (Unix seconds) unless it's at its highest or one is
## under way already. Returns whether it started. Paying for it (`next_cost`, which the job keeps)
## is up to the caller (see `PlayerHold.pay`).
func start(upgrade: Upgrade, now: float) -> bool:
	var next: UpgradeLevel = next_level(upgrade)
	if not next or is_running(upgrade):
		return false
	jobs[upgrade] = TimedJob.new(mk(upgrade) + 1, now, next.seconds, next_cost(upgrade))
	emit_changed()
	return true


## Stops the level of `upgrade` under way. Returns what was paid for it (empty when none was), for
## the caller to give back.
func stop(upgrade: Upgrade) -> Dictionary[ItemType, int]:
	var job: TimedJob = get_job(upgrade)
	if not job:
		return {}
	jobs.erase(upgrade)
	emit_changed()
	return job.paid.duplicate()


## Lets every level done by `now` (Unix seconds) take effect. Returns those upgrades.
func update(now: float) -> Array[Upgrade]:
	var done: Array[Upgrade] = []
	for upgrade: Upgrade in jobs:
		if jobs[upgrade].is_done(now):
			done.append(upgrade)
	return _finish(done)


## Lets every level under way take effect right now (the debug overlay).
func finish_all() -> Array[Upgrade]:
	var all: Array[Upgrade] = []
	all.assign(jobs.keys())
	return _finish(all)


## Puts `job` under way for `upgrade` as saved (no paying). Returns whether it fits: the level
## after the current one.
func restore(upgrade: Upgrade, job: TimedJob) -> bool:
	if not upgrade or job.level != mk(upgrade) + 1 or job.level > upgrade.max_mk():
		return false
	jobs[upgrade] = job
	emit_changed()
	return true


## Raises `upgrade` by one MK level at once unless it's at its highest (the debug overlay, tests).
## Returns whether it rose. Paying for it is up to the caller (see `PlayerHold.pay`).
func raise(upgrade: Upgrade) -> bool:
	if not next_level(upgrade):
		return false
	levels[upgrade] = mk(upgrade) + 1
	if is_running(upgrade) and jobs[upgrade].level <= levels[upgrade]:
		jobs.erase(upgrade)
	emit_changed()
	return true


## What's saved: the MK level per upgrade and the levels under way (`TimedJob.save_data`).
func save_data() -> Dictionary:
	var saved_jobs: Dictionary = {}
	for upgrade: Upgrade in jobs:
		saved_jobs[SaveData.uid_of(upgrade)] = jobs[upgrade].save_data()
	return {"levels": SaveData.numbers_by_uid(levels), "jobs": saved_jobs}


## Reads what a save has (`save_data`), only the upgrades in `only` unless it's empty; levels
## out of range are clamped, levels under way that don't fit skipped. Those done since take effect
## with `update`. Returns whether all of it read.
func load_data(saved: Variant, only: Array[Upgrade] = []) -> bool:
	if saved == null:
		return true
	var data: Dictionary = saved if saved is Dictionary else {}
	var saved_levels: Variant = data.get("levels", {})
	var saved_jobs: Variant = data.get("jobs", {})
	if not saved is Dictionary or not saved_levels is Dictionary or not saved_jobs is Dictionary:
		return SaveData.skipped("upgrades", saved)
	var entries: Dictionary = saved_levels
	var read: Dictionary = SaveData.load_numbers(entries, Upgrade, 1.0, "upgrade")
	var complete: bool = read.size() == entries.size()
	for upgrade: Upgrade in read:
		var level: float = read[upgrade]
		if only.is_empty() or upgrade in only:
			levels[upgrade] = clampi(roundi(level), 1, upgrade.max_mk())
		else:
			complete = SaveData.skipped("upgrade", SaveData.uid_of(upgrade))
	entries = saved_jobs
	for key: Variant in entries:
		var upgrade := SaveData.load_uid(key, Upgrade) as Upgrade
		var job: TimedJob = TimedJob.from_data(entries[key])
		var fits: bool = upgrade and job and (only.is_empty() or upgrade in only)
		if not fits or not restore(upgrade, job):
			complete = SaveData.skipped("upgrade job", key)
	emit_changed()
	return complete


func _finish(done: Array[Upgrade]) -> Array[Upgrade]:
	if done.is_empty():
		return done
	for upgrade: Upgrade in done:
		levels[upgrade] = maxi(mk(upgrade), jobs[upgrade].level)
		jobs.erase(upgrade)
	emit_changed()
	for upgrade: Upgrade in done:
		finished.emit(upgrade)
	return done
