class_name Refining
extends Resource
## A player's batches in the refinery's furnaces (`AlloyBatch`, one per furnace slot): each player
## refines from their own hold into their own, in their own save (like their `Upgrades`); how many
## furnaces there are is the ship's (`Furnaces`). A batch is paid when it starts and runs on the
## wall clock, also during runs and while the game is closed: `update` puts every bar finished by
## then into the hold (the ship's `Refinery` calls it every second, the save on loading), and a
## batch whose last bar is done leaves its furnace free.

## Emitted when `count` bars of `alloy` from `slot`'s furnace went into the hold.
signal bars_finished(slot: int, alloy: AlloyType, count: int)

## Furnaces a ship can have.
const SLOTS: int = 4

## The batch in each furnace slot (null: free).
var batches: Array[AlloyBatch] = []


func _init() -> void:
	batches.resize(SLOTS)


## The batch in `slot`'s furnace, or null.
func get_batch(slot: int) -> AlloyBatch:
	return batches[slot] if slot >= 0 and slot < SLOTS else null


## Whether `slot`'s furnace is free and `hold` pays for `bars` bars of `alloy` (one at least).
func can_start(slot: int, alloy: AlloyType, bars: int, hold: PlayerHold) -> bool:
	return (
		slot >= 0
		and slot < SLOTS
		and not batches[slot]
		and alloy != null
		and bars >= 1
		and hold.can_pay(alloy.cost(bars))
	)


## Starts `bars` bars of `alloy` in `slot`'s furnace at `now` (Unix seconds), paid from `hold`.
## Returns whether it started.
func start(slot: int, alloy: AlloyType, bars: int, hold: PlayerHold, now: float) -> bool:
	if not can_start(slot, alloy, bars, hold) or not hold.pay(alloy.cost(bars)):
		return false
	batches[slot] = AlloyBatch.new(alloy, bars, now)
	emit_changed()
	return true


## Stops `slot`'s batch at `now`: the bars finished by then go into `hold`, and so does the ore of
## every unfinished one. Returns whether there was one.
func stop(slot: int, hold: PlayerHold, now: float) -> bool:
	_deliver(slot, hold, now)
	var batch: AlloyBatch = get_batch(slot)
	if not batch:
		return false
	hold.refund(batch.unfinished_cost())
	batches[slot] = null
	emit_changed()
	return true


## Puts every bar finished by `now` (Unix seconds) into `hold`. Returns how many.
func update(hold: PlayerHold, now: float) -> int:
	var count: int = 0
	for slot: int in SLOTS:
		count += _deliver(slot, hold, now)
	return count


## Finishes every bar of every batch right now (the debug overlay).
func finish_all(hold: PlayerHold) -> void:
	for slot: int in SLOTS:
		var batch: AlloyBatch = batches[slot]
		if batch:
			_deliver(slot, hold, batch.started + batch.bars * batch.alloy.seconds_per_bar)


## Puts `batch` into `slot` as saved (no paying, nothing delivered yet).
func restore(slot: int, batch: AlloyBatch) -> void:
	if slot >= 0 and slot < SLOTS:
		batches[slot] = batch
		emit_changed()


func _deliver(slot: int, hold: PlayerHold, now: float) -> int:
	var batch: AlloyBatch = get_batch(slot)
	if not batch:
		return 0
	var count: int = batch.finished_at(now) - batch.done
	if count <= 0:
		return 0
	batch.done += count
	hold.add(batch.alloy, count)
	if batch.done >= batch.bars:
		batches[slot] = null
	bars_finished.emit(slot, batch.alloy, count)
	emit_changed()
	return count
