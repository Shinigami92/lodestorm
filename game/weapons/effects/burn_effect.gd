class_name BurnEffect
extends WeaponEffect
## Sets what a hit lands on burning (Scald's flame, see `Burning`): damage per second for a few
## seconds (longer with the MK level of the weapon's burn). All values TBD (playtest).

## Damage per second while it burns.
@export var damage_per_second: float = 6.0
## Seconds it burns at MK1, counted from the last hit.
@export var seconds: float = 3.0


func add_to(hit: Hit, weapon: Weapon) -> void:
	hit.burn_damage = maxf(hit.burn_damage, damage_per_second)
	hit.burn_time = maxf(hit.burn_time, seconds * weapon.multiplier(WeaponPart.Stat.BURN))
