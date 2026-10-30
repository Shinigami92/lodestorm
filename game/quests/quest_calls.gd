class_name QuestCalls
extends RefCounted
## The radio calls heard of the accepted quests' active steps (see `QuestRadio`), kept with the
## `QuestLog` and saved with it: a landing line is heard once per step, and the step's NPC says the
## ones heard again when its entry is picked (`lines`). Forgotten once the step is handed in.

## Per quest (its id): the keys of its active step's calls heard (`QuestStep.radio_line`), in the
## order they were.
var heard: Dictionary[StringName, PackedStringArray] = {}


## Counts the call `key` of `quest`'s active step as heard. Returns whether it wasn't yet.
func hear(quest: Quest, key: StringName) -> bool:
	var keys: PackedStringArray = heard.get(quest.id, PackedStringArray())
	if String(key) in keys:
		return false
	keys.append(String(key))
	heard[quest.id] = keys
	return true


## The lines of `step` (`quest`'s active one) heard so far, oldest first, worded for several
## players `together` or one (English).
func lines(quest: Quest, step: QuestStep, together: bool) -> Array[String]:
	var found: Array[String] = []
	for key: String in heard.get(quest.id, PackedStringArray()):
		var said: RadioLine = step.radio_line(StringName(key))
		if said and not said.for_players(together).is_empty():
			found.append(said.for_players(together))
	return found


## Forgets what's heard of `quest`'s step (handed in, or a new one starting).
func forget(quest: Quest) -> void:
	heard.erase(quest.id)


## What's saved: the keys heard per quest.
func save_data() -> Dictionary:
	var saved: Dictionary = {}
	for id: StringName in heard:
		saved[String(id)] = Array(heard[id])
	return saved


## Reads what a save has (`save_data`), only for the quests `accepted`. Returns whether all of it
## read.
func load_data(saved: Variant, accepted: Array[StringName]) -> bool:
	heard.clear()
	if saved == null:
		return true
	if not saved is Dictionary:
		return SaveData.skipped("quest calls", saved)
	var complete: bool = true
	for id: Variant in saved as Dictionary:
		var keys: Variant = (saved as Dictionary)[id]
		if not id is String or StringName(id as String) not in accepted or not keys is Array:
			complete = SaveData.skipped("quest calls", id)
			continue
		var read := PackedStringArray()
		for key: Variant in keys as Array:
			if key is String:
				read.append(key as String)
			else:
				complete = SaveData.skipped("quest call", key)
		heard[StringName(id as String)] = read
	return complete
