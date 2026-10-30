class_name QuestCondition
extends BeatCondition
## A quest's step being done now, or done: `step` of the quest `quest` (their ids); without a
## step, the quest itself (active: accepted with a step to do).

## Saved by number in resources: add new values at the end.
enum State { ACTIVE, DONE }

@export var quest: StringName
## Its `QuestStep.id`; empty: the whole quest.
@export var step: StringName = &""
@export var state: State = State.ACTIVE


func holds(director: StoryDirector, _beat: Beat) -> bool:
	var quest_log: QuestLog = director.quests
	var found: Quest = quest_log.catalog.find(quest)
	if not found:
		return false
	var current: QuestStep = quest_log.current_step(found)
	if step.is_empty():
		return current != null if state == State.ACTIVE else quest_log.is_done(found)
	if state == State.ACTIVE:
		return current != null and current.id == step
	for each: QuestStep in found.steps:
		if each.id == step:
			return director.story.is_set(found.step_flag(each))
	return false
