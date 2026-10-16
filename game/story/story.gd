class_name Story
extends Resource
## What has happened in the story so far, as flags: a topic heard to the end at an NPC (its id),
## later quest steps and crew joining. It's the host's (the ship's), saved with the ship.

## The flags set so far (the value is always true).
@export var flags: Dictionary[StringName, bool] = {}


## Whether `flag` is set.
func is_set(flag: StringName) -> bool:
	return flags.has(flag)


## Whether every flag in `required` is set (true when it's empty).
func is_set_all(required: Array[StringName]) -> bool:
	return required.all(is_set)


## Sets `flag` (once; it stays set).
func set_flag(flag: StringName) -> void:
	if flag.is_empty() or flags.has(flag):
		return
	flags[flag] = true
	emit_changed()
