class_name RegionVisitedCondition
extends BeatCondition
## A region a run went to at least once (`StoryDirector.regions_visited`).

## Its `Region.id`.
@export var region: StringName


func holds(director: StoryDirector, _beat: Beat) -> bool:
	return region in director.regions_visited
