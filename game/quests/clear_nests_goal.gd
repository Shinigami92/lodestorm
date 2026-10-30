class_name ClearNestsGoal
extends RegionGoal
## Destroy an amount of quest nests in a region: while the step is active, every visit places the
## ones still to destroy (with a look of their own, see `AlienNest.Kind`); only those count.

@export_range(1, 20) var amount: int = 2


func describe() -> String:
	return tr("Clear the nests")


func target() -> float:
	return amount


func nests(progress: float) -> int:
	return maxi(amount - floori(progress), 0)
