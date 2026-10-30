@abstract class_name RegionGoal
extends QuestGoal
## A goal done out in one region (see docs/planned/quests.md, Quest sites): while its step is
## active, every visit to the region gets what it needs (a `QuestVisit`: its quest site, its quest
## nests, the strain it hunts in a brood nest or a lair, fragments in its crates, an item at its
## site), and what's done there counts once someone is back aboard (a carried item once its carrier
## is).

## The region it's done in: its `Region.id`.
@export var region: StringName


## The map part it puts into the region's visits as its quest site (a set piece while its step is
## active), or null.
func site() -> PartPlacement:
	return null


## How many quest nests it puts into a visit, with `progress` so far; none by default.
func nests(_progress: float) -> int:
	return 0


## The strain it hunts at its site, or null (none by default).
func hunted() -> AlienStrain:
	return null


## The brood nest it puts at its site, hatching `hunted`, or null: none, or `hunted` sleeps in a
## lair there.
func brood_nest() -> PackedScene:
	return null


## How many blueprint fragments it puts into a visit's crates, with `progress` so far; none by
## default.
func fragments(_progress: float) -> int:
	return 0


## The look of the item it puts at its site to recover, or null (none by default).
func item_look() -> PackedScene:
	return null
