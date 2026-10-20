@abstract class_name WeaponEffect
extends Resource
## What a weapon's hit does (see `WeaponType.effects`): damage (`DamageEffect`), burning
## (`BurnEffect`), healing (`HealEffect`), slowing (`SlowEffect`) and throwing (`ThrowEffect`).
## All values TBD (playtest).

## Adds this effect to `hit`, made by `weapon` (its MK levels scale it).
@abstract func add_to(hit: Hit, weapon: Weapon) -> void
