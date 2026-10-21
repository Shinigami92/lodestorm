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


## The highest MK level.
func max_mk() -> int:
	return levels.size() + 1


## The level that turns MK `mk` into the next one, or null at the highest.
func level_after(mk: int) -> UpgradeLevel:
	return levels[mk - 1] if mk >= 1 and mk <= levels.size() else null


## How much MK `mk` improves the values (1 at MK1).
func multiplier(mk: int) -> float:
	return levels[mk - 2].multiplier if mk >= 2 and mk <= max_mk() else 1.0


## What raising it to MK `mk` costs, in units per ore type (empty for MK1 or beyond the highest).
func cost_of(mk: int) -> Dictionary[OreType, int]:
	if mk > max_mk():
		return {}
	return COSTS.cost_of(mk, cost_scale)
