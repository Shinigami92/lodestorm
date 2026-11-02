class_name QuestUndo
extends RefCounted
## What handing in a quest's step changes in a `QuestLog`, to take back (a step handed in out in a
## region during a run that's lost, see `QuestVisit.drop`): the quest's progress, the quest tracked
## and its calls heard as they were before (`before`), and the story flags the hand-in set
## (`after`). Such a step pays nothing but a crew member joining, so there's nothing else to take
## back.

## Whose step it is.
var quest: Quest

var _progress: PackedFloat64Array
var _tracked: StringName
var _heard: PackedStringArray
## The flags the hand-in may set (not set before it), then those it did set.
var _flags: Array[StringName] = []


## What `quest_log` holds of `quest` before its `step` is handed in.
static func before(quest_log: QuestLog, of_quest: Quest, step: QuestStep) -> QuestUndo:
	var undo := QuestUndo.new()
	undo.quest = of_quest
	var progress: PackedFloat64Array = quest_log.progress.get(of_quest.id, PackedFloat64Array())
	var heard: PackedStringArray = quest_log.calls.heard.get(of_quest.id, PackedStringArray())
	undo._progress = progress.duplicate()
	undo._tracked = quest_log.tracked
	undo._heard = heard.duplicate()
	var flags: Array[StringName] = [of_quest.step_flag(step), of_quest.flag()]
	if not step.join_flag().is_empty():
		flags.append(step.join_flag())
	for flag: StringName in flags:
		if not quest_log.story.is_set(flag):
			undo._flags.append(flag)
	return undo


## Keeps the flags the hand-in set in `quest_log` (once it's handed in).
func after(quest_log: QuestLog) -> void:
	_flags = _flags.filter(func(flag: StringName) -> bool: return quest_log.story.is_set(flag))


## Takes the hand-in back in `quest_log`: its flags cleared, the progress, calls heard and the
## quest tracked as before (`changed` isn't emitted: the caller does once it's done).
func apply(quest_log: QuestLog) -> void:
	for flag: StringName in _flags:
		quest_log.story.clear_flag(flag)
	quest_log.progress[quest.id] = _progress
	quest_log.calls.heard[quest.id] = _heard
	quest_log.tracked = _tracked
