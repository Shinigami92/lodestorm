class_name OreFoundCondition
extends BeatCondition
## An ore brought aboard at least once (`StoryDirector.ores_found`).

@export var ore: OreType


func holds(director: StoryDirector, _beat: Beat) -> bool:
	return ore in director.ores_found
