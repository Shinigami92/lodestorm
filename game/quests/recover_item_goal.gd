class_name RecoverItemGoal
extends RegionGoal
## Recover an item at a site in a region (see docs/planned/quests.md, Blueprint fragments and quest
## items): while the step is active, every visit puts its site's map part in with the item at the
## part's quest anchor (a `QuestItem`). It's carried on the back and counts once its carrier is
## aboard; it's lost when they die and lies at its site again on a later visit.

## The map part of the site (with a quest anchor where the item lies; else its middle).
@export var site_part: PartPlacement
## What it is, on the cards and the quest board (the English text, translated), e.g. "the survey
## team's case".
@export var item: String
## Its look (a scene from `game/quests/items/`): where it lies and on the back.
@export var item_scene: PackedScene


func describe() -> String:
	return tr("Recover %s") % tr(item)


func site() -> PartPlacement:
	return site_part


func item_look() -> PackedScene:
	return item_scene
