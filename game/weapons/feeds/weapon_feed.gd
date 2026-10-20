@abstract class_name WeaponFeed
extends Resource
## What feeds a weapon (see `WeaponType.feed`): the settings of its ammo. Every weapon fed by it
## gets its own `WeaponAmmo` (`create_ammo`) keeping its rounds and reloads. Melee weapons have
## none: magazines, belts and single rounds (`MagazineFeed`), batteries (`BatteryFeed`) and fuel
## cells that heat up (`HeatFeed`); a shield's field charge (`FieldFeed`) is fed like them, but
## isn't ammo. All values TBD (playtest).

## Ore one round costs, in units of the commonest ore (see `OreType.ammo_yield`); 0: free.
@export var ore_per_round: float = 0.25

## The ammo of `weapon`, which this feeds.
@abstract func create_ammo(weapon: Weapon) -> WeaponAmmo


## Whether its rounds are ammo its attacks use; a shield's field charge isn't (its weapon is a melee
## weapon).
func is_ammo() -> bool:
	return true
