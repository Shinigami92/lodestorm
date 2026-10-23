class_name PlayerVitals
extends Node
## The `holder`'s health, from 0 to `maximum()` (the suit's health with the skills, times the
## armor upgrade), shown on the suit light (`light`). Damage flashes the light; with the
## regeneration skill it heals by itself once no damage came for a while; at zero the holder is
## dead (`died`) until `revive`. The holder passes it on as `Player.take_damage`, `heal` and
## `respawn`, and tells it about every physics step (`update`) and a new maximum (`update_maximum`).

## Emitted when health changes (damage, healing).
signal changed(health: float)
## Emitted on damage, with where it came from (`Vector3.INF`: nowhere in particular, e.g. the
## storm).
signal hurt(amount: float, from: Vector3)
## Emitted when health reaches zero.
signal died

## The debug overlay's god mode: no player loses health (hits still flash the light and mark the
## suit ring).
static var god_mode: bool = false

## The player whose health it is.
var holder: Player
## Shows the health and the regeneration.
var light: SuitLight
## Current health, from 0 to `maximum()`.
var health: float
## A dead player can't move or act until revived.
var dead: bool = false
## Whether it heals by itself right now (the regeneration skill).
var regenerating: bool = false

## Seconds since the last damage (for regeneration).
var _since_damage: float = INF
## `maximum()` when health was last set, so a stronger armor or more health from skills adds the
## difference.
var _maximum: float


## Health when unhurt, with the skills and the armor upgrade.
func maximum() -> float:
	var settings: PlayerSettings = holder.settings
	return (
		(settings.max_health + holder.skills.value(Skill.Effect.HEALTH))
		* holder.upgrades.multiplier(holder.armor_upgrade)
	)


## Loses `amount` health (from an attacker at `from`, if it has one); dies at zero.
func damage(amount: float, from: Vector3 = Vector3.INF) -> void:
	if dead or amount <= 0.0:
		return
	if god_mode:
		hurt.emit(amount, from)
		light.flash()
		return
	_since_damage = 0.0
	_set_health(health - amount)
	hurt.emit(amount, from)
	if health > 0.0:
		light.flash()
		return
	dead = true
	regenerating = false
	light.regenerating = false
	died.emit()


## Restores `amount` health, all of it by default (not when dead).
func heal(amount: float = INF) -> void:
	if not dead:
		_set_health(minf(health + amount, maximum()))


## Sets the health to `value`, up to the maximum (not when dead): e.g. what a save kept.
func restore(value: float) -> void:
	if not dead:
		_set_health(minf(value, maximum()))


## Alive again with full health.
func revive() -> void:
	dead = false
	_set_health(maximum())


## A new maximum (armor or skills, bought aboard) adds the difference to the health.
func update_maximum() -> void:
	if not dead:
		_set_health(health + maximum() - _maximum)


## Heals by itself with the regeneration skill, once it took no damage for a while.
func update(delta: float) -> void:
	_since_damage += delta
	var rate: float = holder.skills.value(Skill.Effect.REGENERATION)
	regenerating = (
		not dead
		and health < maximum()
		and _since_damage >= holder.settings.regeneration_delay
		and rate > 0.0
	)
	light.regenerating = regenerating
	if regenerating:
		_set_health(health + rate * delta)


func _set_health(value: float) -> void:
	_maximum = maximum()
	health = clampf(value, 0.0, _maximum)
	light.show_health(health / _maximum)
	changed.emit(health)
