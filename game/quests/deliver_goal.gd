class_name DeliverGoal
extends QuestGoal
## Bring an amount of an ore or an alloy (see docs/planned/coop-ore.md): an ore fills from the
## hauls brought aboard while the step is active (after the heat shield's plate), and whatever is
## still missing can be paid from the hold of whoever hands it in. Alloys come only from the hold.

@export var item: ItemType
@export_range(1, 100000) var amount: int = 100


func describe() -> String:
	return tr("Deliver %s") % tr(item.display_name)


func target() -> float:
	return amount


func take_from(haul: Dictionary[OreType, float], progress: float) -> Dictionary[OreType, float]:
	var taken: Dictionary[OreType, float] = {}
	var ore := item as OreType
	var brought: float = haul.get(ore, 0.0) if ore else 0.0
	var amount_taken: float = minf(brought, amount - progress)
	if amount_taken > 0.0:
		taken[ore] = amount_taken
	return taken


func missing(progress: float) -> Dictionary[ItemType, int]:
	var left: Dictionary[ItemType, int] = {}
	if ceili(amount - progress) > 0:
		left[item] = ceili(amount - progress)
	return left
