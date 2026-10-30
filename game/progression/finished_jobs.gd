class_name FinishedJobs
extends Resource
## A player's jobs that finished since they last looked at the quest board's jobs (see
## `QuestBoardStation`): upgrade levels, skill ranks, crafted miners and their parts' levels,
## furnace batches, newest first. Saved with the player, so what finished while the game was
## closed shows too (it finishes when the save is loaded); `clear` once they've seen them.

## The most kept (the oldest go first).
const MOST: int = 30

## Newest first.
var entries: Array[FinishedJob] = []

var _upgrades: Upgrades
var _skills: Skills


## Notes what finishes in `upgrades`, `skills`, `fleet` and `refining` (a player's).
func watch(upgrades: Upgrades, skills: Skills, fleet: MinerFleet, refining: Refining) -> void:
	# Methods, not lambdas: a lambda holding `upgrades` in its own signal would keep it alive.
	_upgrades = upgrades
	_skills = skills
	upgrades.finished.connect(_on_upgrade_finished)
	skills.finished.connect(_on_skill_finished)
	fleet.built.connect(_on_miner_built)
	fleet.part_finished.connect(_on_miner_part_finished)
	refining.batch_finished.connect(_on_batch_finished)


## Adds `job` as the newest, finished now unless it says when.
func add(job: FinishedJob) -> void:
	if job.at <= 0.0:
		job.at = Time.get_unix_time_from_system()
	entries.push_front(job)
	if entries.size() > MOST:
		entries.resize(MOST)
	emit_changed()


## Forgets them (they've been seen).
func clear() -> void:
	if entries.is_empty():
		return
	entries.clear()
	emit_changed()


## What's saved: each one's `FinishedJob.save_data`, newest first.
func save_data() -> Array:
	return entries.map(func(job: FinishedJob) -> Dictionary: return job.save_data())


## Reads what a save has (`save_data`), without entries that don't read. Returns whether all of
## them read.
func load_data(saved: Variant) -> bool:
	if saved == null:
		return true
	if not saved is Array:
		return SaveData.skipped("finished jobs", saved)
	var complete: bool = true
	for entry: Variant in saved as Array:
		var job: FinishedJob = FinishedJob.from_data(entry)
		if job and entries.size() < MOST:
			entries.append(job)
		else:
			complete = SaveData.skipped("finished job", entry)
	emit_changed()
	return complete


func _on_upgrade_finished(upgrade: Upgrade) -> void:
	add(FinishedJob.new(upgrade, _upgrades.mk(upgrade)))


func _on_skill_finished(skill: Skill) -> void:
	add(FinishedJob.new(skill, _skills.rank(skill)))


func _on_miner_built(miner: CraftedMiner) -> void:
	add(FinishedJob.new(null, 1, miner.number))


func _on_miner_part_finished(miner: CraftedMiner, upgrade: Upgrade) -> void:
	add(FinishedJob.new(upgrade, miner.upgrades.mk(upgrade), miner.number))


func _on_batch_finished(_slot: int, alloy: AlloyType, bars: int) -> void:
	add(FinishedJob.new(alloy, bars))
