extends GutTest
## A player's batches in the furnaces (`Refining`, `AlloyBatch`) on the wall clock, and the ship's
## furnaces (`Furnaces`).

const COBREL: AlloyType = preload("res://game/refinery/alloys/alloy_cobrel.tres")
const MERISK: AlloyType = preload("res://game/refinery/alloys/alloy_merisk.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
## Some wall clock time, in Unix seconds.
const NOW: float = 1_800_000_000.0

var _hold: PlayerHold
var _refining: Refining


func before_each() -> void:
	_hold = PlayerHold.new()
	_hold.add(KYRITE, 100.0)
	_hold.add(VYREL, 100.0)
	_refining = Refining.new()


func test_starting_pays_for_every_bar() -> void:
	assert_true(_refining.start(0, COBREL, 4, _hold, NOW))
	assert_eq(_hold.amount(KYRITE), 60.0)
	assert_eq(_hold.amount(VYREL), 80.0)
	var batch: AlloyBatch = _refining.get_batch(0)
	assert_eq(batch.alloy, COBREL)
	assert_eq(batch.bars, 4)
	assert_eq(batch.done, 0)


func test_one_batch_per_furnace() -> void:
	assert_true(_refining.start(0, COBREL, 1, _hold, NOW))
	assert_false(_refining.start(0, COBREL, 1, _hold, NOW), "no adding to a running batch")
	assert_true(_refining.start(1, COBREL, 1, _hold, NOW), "another furnace")
	assert_false(_refining.start(Refining.SLOTS, COBREL, 1, _hold, NOW), "no such furnace")


func test_nothing_starts_without_the_ore() -> void:
	assert_false(_refining.start(0, COBREL, 11, _hold, NOW))
	assert_false(_refining.start(0, MERISK, 1, _hold, NOW))
	assert_false(_refining.start(0, COBREL, 0, _hold, NOW))
	assert_eq(_hold.amount(KYRITE), 100.0, "nothing paid")
	assert_null(_refining.get_batch(0))


func test_bars_finish_one_by_one() -> void:
	var finished: Array[int] = []
	_refining.bars_finished.connect(
		func(_slot: int, _alloy: AlloyType, count: int) -> void: finished.append(count)
	)
	_refining.start(0, COBREL, 3, _hold, NOW)
	var bar: float = COBREL.seconds_per_bar
	assert_eq(_refining.update(_hold, NOW + bar * 0.9), 0)
	assert_eq(_hold.amount(COBREL), 0.0)
	assert_almost_eq(_refining.get_batch(0).bar_progress(NOW + bar * 0.9), 0.9, 0.001)
	assert_eq(_refining.update(_hold, NOW + bar * 1.1), 1)
	assert_eq(_hold.amount(COBREL), 1.0)
	assert_true(_hold.has_found(COBREL))
	assert_almost_eq(_refining.get_batch(0).progress(NOW + bar * 1.5), 0.5, 0.001)
	assert_almost_eq(_refining.get_batch(0).time_left(NOW + bar * 1.5), bar * 1.5, 0.001)
	assert_eq(_refining.update(_hold, NOW + bar * 10.0), 2, "the rest at once after a long time")
	assert_eq(_hold.amount(COBREL), 3.0)
	assert_null(_refining.get_batch(0), "the furnace is free again")
	assert_eq(finished, [1, 2] as Array[int])


func test_a_clock_set_back_takes_nothing_away() -> void:
	_refining.start(0, COBREL, 3, _hold, NOW)
	var bar: float = COBREL.seconds_per_bar
	_refining.update(_hold, NOW + bar * 2.5)
	assert_eq(_hold.amount(COBREL), 2.0)
	assert_eq(_refining.update(_hold, NOW), 0)
	assert_eq(_hold.amount(COBREL), 2.0, "finished bars stay")
	assert_eq(_refining.get_batch(0).done, 2)
	assert_eq(_refining.get_batch(0).bar_progress(NOW), 0.0, "the next bar waits")
	assert_eq(_refining.update(_hold, NOW + bar * 3.0), 1)


func test_stopping_keeps_the_bars_done_and_gives_back_the_rest() -> void:
	_refining.start(0, COBREL, 5, _hold, NOW)
	assert_eq(_hold.amount(KYRITE), 50.0)
	assert_true(_refining.stop(0, _hold, NOW + COBREL.seconds_per_bar * 2.5))
	assert_eq(_hold.amount(COBREL), 2.0)
	assert_eq(_hold.amount(KYRITE), 80.0, "three bars' ore back")
	assert_eq(_hold.amount(VYREL), 90.0)
	assert_null(_refining.get_batch(0))
	assert_false(_refining.stop(0, _hold, NOW), "nothing left to stop")


func test_finish_all() -> void:
	_refining.start(0, COBREL, 2, _hold, NOW)
	_refining.start(1, COBREL, 3, _hold, NOW)
	_refining.finish_all(_hold)
	assert_eq(_hold.amount(COBREL), 5.0)
	assert_null(_refining.get_batch(0))
	assert_null(_refining.get_batch(1))


func test_changes_are_signaled() -> void:
	watch_signals(_refining)
	_refining.start(0, COBREL, 2, _hold, NOW)
	assert_signal_emit_count(_refining, "changed", 1)
	_refining.update(_hold, NOW + COBREL.seconds_per_bar)
	assert_signal_emit_count(_refining, "changed", 2)
	_refining.update(_hold, NOW + COBREL.seconds_per_bar)
	assert_signal_emit_count(_refining, "changed", 2, "nothing new")


func test_furnaces_unlock_one_by_one_up_to_four() -> void:
	var furnaces := Furnaces.new()
	assert_false(furnaces.is_unlocked(0), "none at first")
	for count: int in Refining.SLOTS:
		assert_true(furnaces.unlock())
		assert_true(furnaces.is_unlocked(count))
	assert_false(furnaces.unlock())
	assert_eq(furnaces.unlocked, Refining.SLOTS)
	furnaces.restore(9)
	assert_eq(furnaces.unlocked, Refining.SLOTS, "clamped")
