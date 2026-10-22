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


## What the next level of `upgrade` costs (empty when it's at its highest or null).
func next_cost(upgrade: Upgrade) -> Dictionary[OreType, int]:
	return upgrade.cost_of(mk(upgrade) + 1) if upgrade else {}


## The level of `upgrade` under way, or null.
func get_job(upgrade: Upgrade) -> TimedJob:
	return jobs.get(upgrade, null)


## Whether a level of `upgrade` is under way.
func is_running(upgrade: Upgrade) -> bool:
	return jobs.has(upgrade)


## Starts the next level of `upgrade` at `now` (Unix seconds) unless it's at its highest or one is
## under way already. Returns whether it started. Paying for it is up to the caller (see
## `PlayerHold.pay`).
func start(upgrade: Upgrade, now: float) -> bool:
	var next: UpgradeLevel = next_level(upgrade)
	if not next or is_running(upgrade):
		return false
	jobs[upgrade] = TimedJob.new(mk(upgrade) + 1, now, next.seconds)
	emit_changed()
	return true


## Stops the level of `upgrade` under way. Returns what it cost (empty when none was), for the
## caller to give back.
func stop(upgrade: Upgrade) -> Dictionary[OreType, int]:
	var job: TimedJob = get_job(upgrade)
	if not job:
		return {}
	jobs.erase(upgrade)
	emit_changed()
	return upgrade.cost_of(job.level)


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
