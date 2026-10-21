class_name Upgrades
extends Resource
## The MK levels a player bought at the upgrade stations, per upgrade; everything else is MK1.
## Each player has their own (like their `Arsenal`).

## MK level per upgrade, only those above MK1.
@export var levels: Dictionary[Upgrade, int] = {}


## The MK level of `upgrade` (1 when it's not bought yet or null).
func mk(upgrade: Upgrade) -> int:
	if not upgrade:
		return 1
	var level: int = levels.get(upgrade, 1)
	return level


## How much `upgrade` improves its values right now (1 at MK1 or for null).
func multiplier(upgrade: Upgrade) -> float:
	return upgrade.multiplier(mk(upgrade)) if upgrade else 1.0


## The level to buy next for `upgrade`, or null when it's at its highest.
func next_level(upgrade: Upgrade) -> UpgradeLevel:
	return upgrade.level_after(mk(upgrade)) if upgrade else null


## What the next level of `upgrade` costs (empty when it's at its highest or null).
func next_cost(upgrade: Upgrade) -> Dictionary[OreType, int]:
	return upgrade.cost_of(mk(upgrade) + 1) if upgrade else {}


## Raises `upgrade` by one MK level unless it's at its highest. Returns whether it rose.
## Paying for it is up to the caller (see `PlayerHold.pay`).
func raise(upgrade: Upgrade) -> bool:
	if not next_level(upgrade):
		return false
	levels[upgrade] = mk(upgrade) + 1
	emit_changed()
	return true
