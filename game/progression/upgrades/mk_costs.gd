class_name MkCosts
extends Resource
## What each MK level costs, the same rule for every upgrade (`game/progression/upgrades/
## mk_costs.tres`, see GAME_DESIGN.md, Upgrade stations): MK2 first, up to the highest. Each
## upgrade scales the amounts (`Upgrade.cost_scale`).

## The levels from MK2 on, in order.
@export var levels: Array[MkCost] = []


## The cost of raising an upgrade to MK `mk`, scaled by `scale` (empty for MK1 or beyond the
## highest).
func cost_of(mk: int, scale: float = 1.0) -> Dictionary[ItemType, int]:
	if mk < 2 or mk > levels.size() + 1:
		return {}
	return levels[mk - 2].cost(scale)
