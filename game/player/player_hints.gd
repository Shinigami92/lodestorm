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
