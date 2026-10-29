class_name Skills
extends Resource
## The skill ranks a player learned at the skill graph; everything else is rank 0. Each player has
## their own (like their `Upgrades`). A rank learned runs on the wall clock first (`jobs`, see
## `TimedJob`): one rank per skill at a time, any number of skills at once; it takes effect when
## `update` finds it done (the ship's `ProgressClock` calls it while no mission is underway, the
## save on loading).

## Emitted when the rank under way of `skill` is done and taken effect.
signal finished(skill: Skill)

## Rank per learned skill.
@export var ranks: Dictionary[Skill, int] = {}

## The rank under way per skill.
var jobs: Dictionary[Skill, TimedJob] = {}


## The rank of `skill` (0 when it's not learned or null).
func rank(skill: Skill) -> int:
	if not skill:
		return 0
	var learned: int = ranks.get(skill, 0)
	return learned


## Whether `skill` can be learned: what it requires is learned.
func is_open(skill: Skill) -> bool:
	return skill != null and (not skill.requires or rank(skill.requires) >= 1)


## The rank to learn next for `skill`, or null when it's at its highest.
func next_rank(skill: Skill) -> SkillRank:
	return skill.rank_after(rank(skill)) if skill else null


## The rank of `skill` under way, or null.
func get_job(skill: Skill) -> TimedJob:
	return jobs.get(skill, null)


## Whether a rank of `skill` is under way.
func is_running(skill: Skill) -> bool:
	return jobs.has(skill)


## Starts the next rank of `skill` at `now` (Unix seconds) if it's open, not at its highest and
## none is under way already. Returns whether it started. Paying for it (the rank's cost, which the
## job keeps) is up to the caller (see `PlayerHold.pay`).
func start(skill: Skill, now: float) -> bool:
	var next: SkillRank = next_rank(skill)
	if not is_open(skill) or not next or is_running(skill):
		return false
	jobs[skill] = TimedJob.new(rank(skill) + 1, now, next.seconds, next.cost)
	emit_changed()
	return true


## Stops the rank of `skill` under way. Returns what was paid for it (empty when none was), for
## the caller to give back.
func stop(skill: Skill) -> Dictionary[ItemType, int]:
	var job: TimedJob = get_job(skill)
	if not job:
		return {}
	jobs.erase(skill)
	emit_changed()
	return job.paid.duplicate()


## Lets every rank done by `now` (Unix seconds) take effect. Returns those skills.
func update(now: float) -> Array[Skill]:
	var done: Array[Skill] = []
	for skill: Skill in jobs:
		if jobs[skill].is_done(now):
			done.append(skill)
	return _finish(done)


## Lets every rank under way take effect right now (the debug overlay).
func finish_all() -> Array[Skill]:
	var all: Array[Skill] = []
	all.assign(jobs.keys())
	return _finish(all)


## Puts `job` under way for `skill` as saved (no paying). Returns whether it fits: the rank after
## the current one.
func restore(skill: Skill, job: TimedJob) -> bool:
	if not skill or job.level != rank(skill) + 1 or job.level > skill.max_rank():
		return false
	jobs[skill] = job
	emit_changed()
	return true


## Raises `skill` by one rank at once if it's open and not at its highest (the debug overlay,
## tests). Returns whether it rose. Paying for it is up to the caller (see `PlayerHold.pay`).
func raise(skill: Skill) -> bool:
	if not is_open(skill) or not next_rank(skill):
		return false
	ranks[skill] = rank(skill) + 1
	if is_running(skill) and jobs[skill].level <= ranks[skill]:
		jobs.erase(skill)
	emit_changed()
	return true


## What the learned skills with `effect` do together (0 when none is learned).
func value(effect: Skill.Effect) -> float:
	var total: float = 0.0
	for skill: Skill in ranks:
		if skill.effect == effect:
			total += skill.value_at(ranks[skill])
	return total


## Whether a skill with `effect` is learned.
func has(effect: Skill.Effect) -> bool:
	for skill: Skill in ranks:
		if skill.effect == effect and ranks[skill] >= 1:
			return true
	return false


## What's saved: the rank per learned skill and the ranks under way (`TimedJob.save_data`).
func save_data() -> Dictionary:
	var saved_jobs: Dictionary = {}
	for skill: Skill in jobs:
		saved_jobs[SaveData.uid_of(skill)] = jobs[skill].save_data()
	return {"ranks": SaveData.numbers_by_uid(ranks), "jobs": saved_jobs}


## Reads what a save has (`save_data`); ranks out of range are clamped, ranks under way that don't
## fit skipped. Those done since take effect with `update`. Returns whether all of it read.
func load_data(saved: Variant) -> bool:
	if saved == null:
		return true
	var data: Dictionary = saved if saved is Dictionary else {}
	var saved_ranks: Variant = data.get("ranks", {})
	var saved_jobs: Variant = data.get("jobs", {})
	if not saved is Dictionary or not saved_ranks is Dictionary or not saved_jobs is Dictionary:
		return SaveData.skipped("skills", saved)
	var entries: Dictionary = saved_ranks
	var read: Dictionary = SaveData.load_numbers(entries, Skill, 1.0, "skill")
	var complete: bool = read.size() == entries.size()
	for skill: Skill in read:
		var learned: float = read[skill]
		ranks[skill] = clampi(roundi(learned), 1, skill.max_rank())
	entries = saved_jobs
	for key: Variant in entries:
		var skill := SaveData.load_uid(key, Skill) as Skill
		var job: TimedJob = TimedJob.from_data(entries[key])
		if not skill or not job or not restore(skill, job):
			complete = SaveData.skipped("skill job", key)
	emit_changed()
	return complete


func _finish(done: Array[Skill]) -> Array[Skill]:
	if done.is_empty():
		return done
	for skill: Skill in done:
		ranks[skill] = maxi(rank(skill), jobs[skill].level)
		jobs.erase(skill)
	emit_changed()
	for skill: Skill in done:
		finished.emit(skill)
	return done
