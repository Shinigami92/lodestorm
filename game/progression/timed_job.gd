class_name TimedJob
extends RefCounted
## An upgrade level or a skill rank under way (see `Upgrades.jobs`, `Skills.jobs`): it reaches
## `level` once `seconds` have passed since `started` on the wall clock (Unix seconds), also during
## runs and while the game is closed. Its time and what was paid for it are kept as they were
## when it started, so retuning the data doesn't shift a running job or what stopping it gives back.
## A clock set back makes it wait, never undoes it.

## The MK level or rank it reaches.
var level: int = 1
## When it started, in Unix seconds.
var started: float = 0.0
## How long it takes, in seconds.
var seconds: float = 0.0
## What was paid for it, in units per item (what stopping it gives back).
var paid: Dictionary[ItemType, int] = {}


func _init(
	to_level: int = 1,
	start_time: float = 0.0,
	duration: float = 0.0,
	paid_for: Dictionary[ItemType, int] = {}
) -> void:
	level = to_level
	started = start_time
	seconds = duration
	paid = paid_for.duplicate()


## Whether it's done at `now` (Unix seconds).
func is_done(now: float) -> bool:
	return now >= started + seconds


## How far it is at `now`, 0–1.
func progress(now: float) -> float:
	return clampf((now - started) / seconds, 0.0, 1.0) if seconds > 0.0 else 1.0


## Seconds until it's done, at `now`.
func time_left(now: float) -> float:
	return clampf(started + seconds - now, 0.0, seconds)


## What's saved: the level it reaches, its start, its time and what was paid.
func save_data() -> Dictionary:
	return {
		"level": level,
		"started": started,
		"seconds": seconds,
		"paid": SaveData.numbers_by_uid(paid)
	}


## A job from what a save has (`save_data`), or null when it doesn't read. Paid entries that don't
## read are skipped.
static func from_data(saved: Variant) -> TimedJob:
	if not saved is Dictionary:
		return null
	var data: Dictionary = saved
	var to_level: float = SaveData.number(data.get("level"), 0.0)
	var start_time: float = SaveData.number(data.get("started"), NAN)
	var duration: float = SaveData.number(data.get("seconds"), -1.0)
	var saved_paid: Variant = data.get("paid", {})
	if to_level < 1.0 or is_nan(start_time) or duration < 0.0 or not saved_paid is Dictionary:
		return null
	var job := TimedJob.new(roundi(to_level), start_time, duration)
	var read: Dictionary = SaveData.load_numbers(saved_paid as Dictionary, ItemType, 0.0, "paid")
	for item: ItemType in read:
		var amount: float = read[item]
		job.paid[item] = roundi(amount)
	return job
