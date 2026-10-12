@abstract class_name Weapon
extends Node3D
## Base of all weapons (ranged and melee): attacks while the trigger is held, limited by the
## attack rate. The holder sets `trigger_held` and `aim_direction`; weapons don't read input.

## The body carrying the weapon, set when it's equipped.
var holder: CollisionObject3D
var trigger_held: bool = false
## Horizontal unit vector the weapon attacks along.
var aim_direction: Vector3 = Vector3.FORWARD
## The alien the holder locked on, or null: attacks go straight at it, up or down slopes too.
var aim_target: Alien
## Scales the damage from the settings, set by the holder from the weapon's MK level.
var damage_multiplier: float = 1.0

## Seconds until the next attack. Keeps the remainder after an attack, so the average attack
## rate doesn't depend on the physics tick rate.
var _cooldown: float = 0.0


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	if trigger_held:
		_attack()
		_cooldown += 1.0 / _get_settings().attack_rate
	else:
		_cooldown = 0.0


## Applies the MK level of `upgrade` (the weapon's, null: MK1) in `upgrades`: the damage and the
## pips on the weapon (an `MkPips` child named `MkPips`, if it has one). Works before the weapon
## enters the tree.
func apply_upgrade(upgrades: Upgrades, upgrade: Upgrade) -> void:
	damage_multiplier = upgrades.multiplier(upgrade)
	var pips := get_node_or_null(^"MkPips") as MkPips
	if pips:
		pips.show_level(upgrades.mk(upgrade), upgrade.max_mk() if upgrade else 1)


## Performs one attack (fire a projectile, swing, ...).
@abstract func _attack() -> void

## Subclasses export their own settings type and return it here.
@abstract func _get_settings() -> WeaponSettings
