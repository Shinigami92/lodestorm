class_name Upgrade
extends Resource
## Something the upgrade stations in the ship improve in MK levels: a weapon, the suit's armor,
## the miners' drill, ... MK1 is what a new player has; each further level costs ore from the
## player's hold (the same rule for every upgrade, `COSTS`, scaled by `cost_scale`) and multiplies
## the values it improves. What it improves is up to its user (e.g. a weapon's `WeaponPart` raises
## one of its values). The levels a player bought are in their `Upgrades`; how high they can go
## depends on the planets the ship has opened (see `HeatShield.upgrade_cap`).

const COSTS: MkCosts = preload("res://game/progression/upgrades/mk_costs.tres")

## Player-facing name.
@export var display_name: String = ""
## One line on what the levels improve, shown at the station.
@export var description: String = ""
## The levels from MK2 on, in order.
@export var levels: Array[UpgradeLevel] = []
## How much its levels cost compared to the standard (`COSTS`, e.g. 0.5: half the ore).
@export var cost_scale: float = 1.0
## Drills only: the hardest ore (`OreType.hardness`) MK1 mines at full speed; the levels raise it
## (`UpgradeLevel.hardness`). -1: not a drill.
@export var hardness: int = -1


## The highest MK level.
func max_mk() -> int:
	return levels.size() + 1


## The level that turns MK `mk` into the next one, or null at the highest.
func level_after(mk: int) -> UpgradeLevel:
	return levels[mk - 1] if mk >= 1 and mk <= levels.size() else null


## How much MK `mk` improves the values (1 at MK1).
func multiplier(mk: int) -> float:
	return levels[mk - 2].multiplier if mk >= 2 and mk <= max_mk() else 1.0


## Drills only: the hardest ore MK `mk` mines at full speed.
func hardness_at(mk: int) -> int:
	return levels[mk - 2].hardness if mk >= 2 and mk <= max_mk() else hardness


## Drills only: the lowest MK level that mines ores of `ore_hardness` at full speed, or 0 if none.
func mk_for_hardness(ore_hardness: int) -> int:
	for mk: int in range(1, max_mk() + 1):
		if hardness_at(mk) >= ore_hardness:
			return mk
	return 0


## What raising it to MK `mk` costs, in units per ore type (empty for MK1 or beyond the highest).
func cost_of(mk: int) -> Dictionary[OreType, int]:
	if mk > max_mk():
		return {}
	return COSTS.cost_of(mk, cost_scale)
