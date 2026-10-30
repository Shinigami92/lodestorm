class_name MineGoal
extends QuestGoal
## Mine an amount of an ore in one run, counted as it's brought aboard: the most one run brought
## while the step is active.

@export var ore: OreType
@export_range(1, 100000) var amount: int = 100


func describe() -> String:
	return tr("Mine %s in one run") % tr(ore.display_name)


func target() -> float:
	return amount


func count_run(run: Dictionary[OreType, float], progress: float) -> float:
	var brought: float = run.get(ore, 0.0)
	return clampf(maxf(progress, brought), 0.0, amount)
