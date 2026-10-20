class_name DamageEffect
extends WeaponEffect
## A hit's damage (scaled by the MK level of the weapon's damage), with the stagger it adds and how
## hard it pushes (see `Hit`). All values TBD (playtest).

## Damage per hit (a projectile, a pellet, a swing) at MK1.
@export var damage: float = 10.0
## Stagger each hit adds to an alien (see `AlienStrain.stagger_threshold`).
@export var stagger: float = 7.0
## How hard each hit pushes an alien back, in m/s (it fades within a fraction of a second).
@export var push: float = 0.5


func add_to(hit: Hit, weapon: Weapon) -> void:
	hit.damage += damage * weapon.multiplier(WeaponPart.Stat.DAMAGE)
	hit.stagger += stagger
	hit.push += push
