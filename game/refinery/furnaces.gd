class_name Furnaces
extends Resource
## How many of the refinery's furnaces the ship has: none at first, the quests unlock them one
## after another (until they exist, the debug overlay does), up to `Refining.SLOTS`. Saved with the
## ship; the batches in them are each player's (`Refining`).

var unlocked: int = 0


## Unlocks the next furnace. Returns whether there was one left.
func unlock() -> bool:
	if unlocked >= Refining.SLOTS:
		return false
	unlocked += 1
	emit_changed()
	return true


## Whether `slot`'s furnace is unlocked.
func is_unlocked(slot: int) -> bool:
	return slot >= 0 and slot < unlocked


## Sets the number unlocked as saved.
func restore(count: int) -> void:
	unlocked = clampi(count, 0, Refining.SLOTS)
	emit_changed()


## What's saved: the number unlocked.
func save_data() -> int:
	return unlocked


## Reads the number unlocked a save has (`save_data`), clamped. Returns whether it read.
func load_data(saved: Variant) -> bool:
	if saved == null:
		return true
	var count: float = SaveData.number(saved, -1.0)
	restore(roundi(clampf(count, 0.0, Refining.SLOTS)))
	if count < 0.0 or count > Refining.SLOTS:
		return SaveData.skipped("furnaces", saved)
	return true
