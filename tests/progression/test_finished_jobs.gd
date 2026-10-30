extends GutTest
## A player's jobs finished since they last looked at the quest board (`FinishedJobs`): what
## finishes is noted newest first, kept in the save and forgotten once seen.

const FULL_HOLD := preload("res://tests/support/full_hold.gd")
const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const DASH: Skill = preload("res://game/progression/skills/tree/dash.tres")
const MERISK: AlloyType = preload("res://game/refinery/alloys/alloy_merisk.tres")

var _jobs: FinishedJobs
var _upgrades: Upgrades
var _skills: Skills
var _fleet: MinerFleet
var _refining: Refining
var _hold: PlayerHold


func before_each() -> void:
	_jobs = FinishedJobs.new()
	_upgrades = Upgrades.new()
	_skills = Skills.new()
	_fleet = MinerFleet.new()
	_refining = Refining.new()
	_hold = FULL_HOLD.fill()
	_jobs.watch(_upgrades, _skills, _fleet, _refining)


func test_every_kind_of_job_is_noted_when_it_finishes() -> void:
	assert_true(_upgrades.start(ARMOR, _hold, 0.0))
	assert_true(_skills.start(DASH, _hold, 0.0))
	var settings := MinerSettings.new()
	settings.build_seconds = 10
	assert_true(_fleet.start_build(2, settings, _hold, 0.0))
	assert_true(_fleet.get_miner(1).upgrades.start(DRILL, _hold, 0.0))
	assert_true(_refining.start(0, MERISK, 2, _hold, 0.0))
	assert_true(_jobs.entries.is_empty(), "nothing done yet")
	var later: float = 1.0e7
	_upgrades.update(later)
	_skills.update(later)
	_fleet.update(later)
	_refining.update(_hold, later)
	var seen: Array[String] = []
	for job: FinishedJob in _jobs.entries:
		seen.append(
			"%s %d %d" % [job.item.resource_path if job.item else "built", job.level, job.miner]
		)
	assert_eq(
		seen,
		(
			[
				"%s 2 0" % MERISK.resource_path,
				"built 1 2",
				"%s 2 1" % DRILL.resource_path,
				"%s 1 0" % DASH.resource_path,
				"%s 2 0" % ARMOR.resource_path,
			]
			as Array[String]
		),
		"newest first"
	)


func test_a_batch_counts_once_its_last_bar_is_done() -> void:
	assert_true(_refining.start(0, MERISK, 2, _hold, 0.0))
	_refining.update(_hold, MERISK.seconds_per_bar)
	assert_true(_jobs.entries.is_empty(), "one bar of two")
	_refining.update(_hold, MERISK.seconds_per_bar * 2.0)
	assert_eq(_jobs.entries.size(), 1)


func test_kept_up_to_the_most() -> void:
	for i: int in FinishedJobs.MOST + 5:
		_jobs.add(FinishedJob.new(MERISK, i + 1, 0, 100.0 + i))
	assert_eq(_jobs.entries.size(), FinishedJobs.MOST)
	assert_eq(_jobs.entries[0].level, FinishedJobs.MOST + 5, "the newest stay")


func test_saved_read_back_and_cleared() -> void:
	_jobs.add(FinishedJob.new(ARMOR, 3, 0, 100.0))
	_jobs.add(FinishedJob.new(null, 1, 2, 200.0))
	_jobs.add(FinishedJob.new(MERISK, 4, 0, 300.0))
	var saved: Array = JSON.parse_string(JSON.stringify(_jobs.save_data()))
	saved.append({"item": "uid://nothing", "level": 1, "at": 1.0})
	saved.append({"item": "", "level": 1, "miner": 0, "at": 1.0})
	var read := FinishedJobs.new()
	assert_false(read.load_data(saved), "the broken ones skipped")
	assert_eq(read.entries.size(), 3)
	assert_eq(read.entries[0].item, MERISK)
	assert_eq(read.entries[1].miner, 2)
	assert_eq(read.entries[2].item, ARMOR)
	assert_eq(read.entries[2].level, 3)
	assert_eq(read.entries[2].at, 100.0)
	assert_true(read.load_data(null), "nothing saved changes nothing")
	watch_signals(read)
	read.clear()
	assert_true(read.entries.is_empty())
	assert_signal_emitted(read, "changed")
