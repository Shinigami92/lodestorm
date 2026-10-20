@abstract class_name Weapon
extends Node3D
## Base of all weapons (ranged and melee): attacks while the trigger is held, limited by the
## attack rate. The holder sets `trigger_held` and `aim_direction`; weapons don't read input.
## Each attack plays the settings' `attack_sound` at the weapon.

## The body carrying the weapon, set when it's equipped.
var holder: CollisionObject3D
var trigger_held: bool = false
## Horizontal unit vector the weapon attacks along.
var aim_direction: Vector3 = Vector3.FORWARD
## The alien or `Destructible` the holder locked on, or null: attacks go straight at it, up or
## down slopes too (see `PlayerAim`).
var aim_target: Node3D
## Scales the damage from the settings, set by the holder from the weapon's MK level.
var damage_multiplier: float = 1.0

## Seconds until the next attack. Keeps the remainder after an attack, so the average attack
## rate doesn't depend on the physics tick rate.
var _cooldown: float = 0.0


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	if trigger_held and _can_attack():
		_attack()
		_play(_get_settings().attack_sound)
		_cooldown += 1.0 / _get_settings().attack_rate
	else:
		_cooldown = 0.0


## Applies the MK levels in `upgrades` of the parts of `weapon_type` (this weapon's, null: all
## MK1): the damage and the pips on the weapon (an `MkPips` child named `MkPips`, if it has one).
## Works before the weapon enters the tree.
func apply_upgrades(upgrades: Upgrades, weapon_type: WeaponType) -> void:
	var upgrade: Upgrade = weapon_type.upgrade if weapon_type else null
	damage_multiplier = upgrades.multiplier(upgrade)
	_show_pips(^"MkPips", upgrades, upgrade)


## Shows the MK level of `upgrade` on the `MkPips` child at `path`, if there is one.
func _show_pips(path: NodePath, upgrades: Upgrades, upgrade: Upgrade) -> void:
	var pips := get_node_or_null(path) as MkPips
	if pips:
		pips.show_level(upgrades.mk(upgrade), upgrade.max_mk() if upgrade else 1)


## Plays `sound` at the weapon. A `cue` (the reload's timing) is only for the local player
## holding it, and a `critical` one always plays and ducks the rest (see `Sfx`).
func _play(sound: Sound, cue: bool = false, critical: bool = false) -> void:
	var local: bool = holder is Player and (holder as Player).local
	if cue and not local:
		return
	Sfx.play_at(sound, global_position, critical and local)


## Whether it can attack right now (e.g. a ranged weapon needs ammo).
func _can_attack() -> bool:
	return true


## Performs one attack (fire a projectile, swing, ...).
@abstract func _attack() -> void

## Subclasses export their own settings type and return it here.
@abstract func _get_settings() -> WeaponSettings
