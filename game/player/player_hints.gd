class_name PlayerHints
extends Resource
## The one-time hints a player has seen (e.g. `RampHint`'s, where to heal), saved with the player:
## each shows once per player, whoever's ship they're on (the story is the host's, see `Story`).

## The hints seen so far (the value is always true).
@export var seen: Dictionary[StringName, bool] = {}


## Whether `hint` was seen.
func is_seen(hint: StringName) -> bool:
	return seen.has(hint)


## Marks `hint` as seen (once).
func mark_seen(hint: StringName) -> void:
	if hint.is_empty() or seen.has(hint):
		return
	seen[hint] = true
	emit_changed()


## What's saved: the hints seen, sorted.
func save_data() -> Array:
	var saved: Array = []
	for hint: StringName in seen:
		saved.append(String(hint))
	saved.sort()
	return saved


## Reads the hints a save has (`save_data`). Returns whether all of them read.
func load_data(saved: Variant) -> bool:
	if saved == null:
		return true
	if not saved is Array:
		return SaveData.skipped("hints", saved)
	var complete: bool = true
	for hint: Variant in saved as Array:
		if hint is String and not (hint as String).is_empty():
			seen[StringName(hint as String)] = true
		else:
			complete = SaveData.skipped("hint", hint)
	emit_changed()
	return complete
