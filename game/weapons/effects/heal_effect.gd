class_name HealEffect
extends WeaponEffect
## Health a hit restores to a teammate, or a miner's it repairs (Kith's beam, see
## `BeamDelivery.mends`), more with the MK level of the weapon's heal rate. All values TBD
## (playtest).

## Health per hit at MK1 (a beam hits at its weapon's attack rate).
@export var heal: float = 2.0


func add_to(hit: Hit, weapon: Weapon) -> void:
	hit.heal += heal * weapon.multiplier(WeaponPart.Stat.HEAL)
