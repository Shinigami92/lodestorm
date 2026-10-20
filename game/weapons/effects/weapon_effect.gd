@abstract class_name WeaponEffect
extends Resource
## What a weapon's hit does (see `WeaponType.effects`): damage (`DamageEffect`) so far; burn,
## shock, knockback, pull and heal are planned (see docs/planned/weapons.md). All values TBD
## (playtest).

## Adds this effect to `hit`, made by `weapon` (its MK levels scale it).
@abstract func add_to(hit: Hit, weapon: Weapon) -> void
