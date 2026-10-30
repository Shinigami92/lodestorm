class_name BuildGoal
extends QuestGoal
## Build something aboard, which teaches its station: a weapon (from its blueprint), an upgrade
## to a level, or a crafted miner. Set one of them; done once a player has it (also when they had
## it before the step started).

## A weapon to own.
@export var weapon: WeaponType
## An upgrade to raise to `mk`.
@export var upgrade: Upgrade
@export_range(1, 10) var mk: int = 2
## A crafted miner to build (any).
@export var miner: bool = false


func describe() -> String:
	if weapon:
		return tr("Build %s") % weapon.display_name
	if upgrade:
		return tr("Raise %s to MK%d") % [tr(upgrade.display_name), mk]
	return tr("Build a miner")


func is_built(players: Array[Player]) -> bool:
	for player: Player in players:
		if weapon and player.arsenal.owns(weapon):
			return true
		if upgrade and player.upgrades.mk(upgrade) >= mk:
			return true
		if miner and not player.fleet.miners.is_empty():
			return true
	return false
