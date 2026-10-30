@abstract class_name RegionGoal
extends QuestGoal
## A goal done out in one region (see docs/planned/quests.md, Quest sites): while its step is
## active, every visit to the region gets what it needs (a `QuestVisit`: its quest site, its quest
## nests), and what's done there counts once someone is back aboard.

## The region it's done in: its `Region.id`.
@export var region: StringName


## The map part it puts into the region's visits as its quest site (a set piece while its step is
## active), or null.
func site() -> PartPlacement:
	return null


## How many quest nests it puts into a visit, with `progress` so far; none by default.
func nests(_progress: float) -> int:
	return 0
