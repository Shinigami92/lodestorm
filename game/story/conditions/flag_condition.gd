class_name FlagCondition
extends BeatCondition
## Story flags: all of `flags` set and none of `unless` (e.g. a topic heard, a crew member not
## aboard yet).

@export var flags: Array[StringName] = []
@export var unless: Array[StringName] = []


func holds(director: StoryDirector, _beat: Beat) -> bool:
	return director.story.is_set_all(flags) and not unless.any(director.story.is_set)
