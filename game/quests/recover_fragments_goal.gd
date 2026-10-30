class_name RecoverFragmentsGoal
extends RegionGoal
## Recover the fragments of a blueprint in a region (see docs/planned/quests.md, Blueprint fragments
## and quest items): while the step is active, the region's crates hold the ones still to find, one
## per crate (`BlueprintFragment`), so it may take several runs. A fragment is carried on the back
## and counts once its carrier is aboard; it's lost when they die and lies in a crate again on a
## later visit. Its `site_part` (a map part with a crate) puts at least one crate into every visit.

@export_range(1, 10) var amount: int = 3
## A map part with a crate marker, placed in every visit while the step is active (e.g. a wreck), so
## there's always a crate to find one in; null: only the region's own crates.
@export var site_part: PartPlacement


func describe() -> String:
	return tr("Recover the blueprint fragments")


func target() -> float:
	return amount


func site() -> PartPlacement:
	return site_part


func fragments(progress: float) -> int:
	return maxi(amount - floori(progress), 0)
