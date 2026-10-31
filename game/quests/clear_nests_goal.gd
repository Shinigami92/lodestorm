class_name ClearNestsGoal
extends RegionGoal
## Destroy an amount of quest nests in a region: while the step is active, every visit places the
## ones still to destroy (with a look of their own, see `AlienNest.Kind`); only those count. With a
## `site_part`, they grow at its `PartMarker.Kind.QUEST_NEST` markers (e.g. around Hollis' miner at
## his camp), else spread over the region.

@export_range(1, 20) var amount: int = 2
## The map part they grow at (its quest nest markers, one nest each); null: anywhere.
@export var site_part: PartPlacement
## What it says on the cards instead of "Clear the nests" (the English text, translated), e.g.
## "Clear the nest around his miner"; empty: that.
@export var task: String = ""


func describe() -> String:
	return tr(task) if not task.is_empty() else tr("Clear the nests")


func target() -> float:
	return amount


func site() -> PartPlacement:
	return site_part


func nests(progress: float) -> int:
	return maxi(amount - floori(progress), 0)
