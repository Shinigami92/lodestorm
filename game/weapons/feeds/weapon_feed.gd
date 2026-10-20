@abstract class_name WeaponFeed
extends Resource
## What feeds a weapon (see `WeaponType.feed`): the settings of its ammo. Every weapon fed by it
## gets its own `WeaponAmmo` (`create_ammo`) keeping its rounds and reloads. Melee weapons have
## none. So far magazines and single rounds (`MagazineFeed`); belts, heat and batteries are
## planned (see docs/planned/weapons.md). All values TBD (playtest).

## Ore one round costs, in units of the commonest ore (see `OreType.ammo_yield`); 0: free.
@export var ore_per_round: float = 0.25

## The ammo of `weapon`, which this feeds.
@abstract func create_ammo(weapon: Weapon) -> WeaponAmmo
