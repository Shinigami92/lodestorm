class_name AlloyBatch
extends RefCounted
## One furnace's batch (see `Refining`): `bars` bars of `alloy`, started at `started` on the wall
## clock (Unix seconds), finishing one by one every `AlloyType.seconds_per_bar`. `done` bars are
## in the hold already; a clock set back never takes them away, the next bar just waits.

var alloy: AlloyType
var bars: int = 1
## Bars finished and put into the hold.
var done: int = 0
## When it started, in Unix seconds.
var started: float = 0.0


func _init(of_alloy: AlloyType = null, bar_count: int = 1, start_time: float = 0.0) -> void:
	alloy = of_alloy
	bars = bar_count
	started = start_time


## Bars finished at `now` (Unix seconds), never fewer than `done`.
func finished_at(now: float) -> int:
	var elapsed: int = floori((now - started) / alloy.seconds_per_bar)
	return clampi(elapsed, done, bars)


## How far the whole batch is at `now`, 0–1.
func progress(now: float) -> float:
	return clampf((done + bar_progress(now)) / bars, 0.0, 1.0)


## How far the bar in the furnace is at `now`, 0–1 (0 once every bar is done).
func bar_progress(now: float) -> float:
	if done >= bars:
		return 0.0
	return clampf((now - started) / alloy.seconds_per_bar - done, 0.0, 1.0)


## Seconds until the last bar is done, at `now`.
func time_left(now: float) -> float:
	return maxf(started + bars * alloy.seconds_per_bar - now, 0.0)


## What its unfinished bars took from the hold, in units per ore.
func unfinished_cost() -> Dictionary[ItemType, int]:
	return alloy.cost(bars - done)


## What's saved: the alloy, the bars, how many are done and when it started.
func save_data() -> Dictionary:
	return {"alloy": SaveData.uid_of(alloy), "bars": bars, "done": done, "started": started}


## A batch from what a save has (`save_data`), or null when it doesn't read.
static func from_data(saved: Variant) -> AlloyBatch:
	if not saved is Dictionary:
		return null
	var data: Dictionary = saved
	var of_alloy := SaveData.load_uid(data.get("alloy"), AlloyType) as AlloyType
	var bar_count: int = roundi(SaveData.number(data.get("bars"), 0.0))
	var bars_done: int = roundi(SaveData.number(data.get("done"), -1.0))
	var start_time: float = SaveData.number(data.get("started"), NAN)
	if not of_alloy or bar_count < 1 or bars_done < 0 or bars_done >= bar_count:
		return null
	if is_nan(start_time):
		return null
	var batch := AlloyBatch.new(of_alloy, bar_count, start_time)
	batch.done = bars_done
	return batch
