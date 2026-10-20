class_name WeaponPart
extends Upgrade
## One part of a weapon that the workbench upgrades in MK levels (see `WeaponType.parts`): each
## level multiplies one of the weapon's values (`stat`, see `Weapon.multiplier`). The pips on the
## weapon showing its level are the weapon scene's child named after the stat (`pips_name`, e.g.
## `DamagePips`), if it has one.

## The value a part improves: the damage per hit, the capacity (rounds per magazine, shells per
## load, shots per battery), attacks per second (melee: swing speed), pellets per shot, a swing's
## arc, how quickly barrels spin up, a charge fills and a battery recharges, a blast's radius and
## how many charges can lie on the ground at once, how long a flame burns, how much a beam heals,
## how far it reaches and how slowly heat builds.
enum Stat {
	DAMAGE,
	CAPACITY,
	RATE,
	PELLETS,
	ARC,
	SPIN,
	CHARGE,
	RECHARGE,
	BLAST,
	CHARGES,
	BURN,
	HEAL,
	RANGE,
	COOLING,
}

@export var stat: Stat = Stat.DAMAGE


## The name of the weapon scene's pips child showing its MK level.
func pips_name() -> StringName:
	return StringName("%sPips" % (Stat.keys()[stat] as String).capitalize())
