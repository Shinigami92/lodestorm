class_name ReachGoal
extends RegionGoal
## Reach a site in a region (find the expedition's camp, scan a wreck): its map part stands in the
## region's visits while the step is active, and walking into it does it (see `QuestSite`).

## The map part of the site (with a quest anchor where it's reached; else its middle).
@export var site_part: PartPlacement
## What the site is, on the cards and the quest board (the English text, translated), e.g. "the
## expedition's camp".
@export var place: String


func describe() -> String:
	return tr("Find %s") % tr(place)


func site() -> PartPlacement:
	return site_part
