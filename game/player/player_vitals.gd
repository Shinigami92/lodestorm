class_name PlayerVitals
extends Node
## The `holder`'s health, from 0 to `maximum()` (the suit's health with the skills, times the
## armor upgrade), shown on the suit light (`light`). Damage flashes the light; with the
## regeneration skill it heals by itself once no damage came for a while. At zero the holder's
## `life` ends: it dies (`died`) until `revive`, or, while `bleed_out` is set (the rescue drone,
## reviving each other in co-op), it goes down first (`went_down`): it lies at zero, takes no damage
## and either `get_up`s again or dies once the bleed-out ran out. The holder passes it on as
## `Player.take_damage`, `heal` and `respawn`, and tells it about every physics step (`update`) and
## a new maximum (`update_maximum`).

## Emitted when health changes (damage, healing).
signal changed(health: float)
## Emitted on damage, with where it came from (`Vector3.INF`: nowhere in particular, e.g. the
## storm).
signal hurt(amount: float, from: Vector3)
## Emitted when health reaches zero while `bleed_out` is set: the holder is down.
signal went_down
## Emitted when a downed holder gets up again (`get_up`).
signal got_up
## Emitted when the holder dies: at zero health, or once a bleed-out ran out.
signal died

## Standing (`ALIVE`), lying at zero health until it gets up or bleeds out (`DOWN`), or `DEAD`
## until revived.
enum Life { ALIVE, DOWN, DEAD }

## The debug overlay's god mode: no player loses health (hits still flash the light and mark the
## suit ring).
static var god_mode: bool = false

## The player whose health it is.
var holder: Player
## Shows the health and the regeneration.
var light: SuitLight
## Current health, from 0 to `maximum()`.
var health: float
## Where the holder stands in life.
var life: Life = Life.ALIVE
## A dead player can't move or act until revived.
var dead: bool:
	get:
		return life == Life.DEAD
## A downed player lies still until it gets up or dies.
var down: bool:
	get:
		return life == Life.DOWN
## Seconds a holder at zero health stays down before it dies; 0 dies at once.
var bleed_out: float = 0.0
## Seconds left until a downed holder dies.
var bleed_out_left: float = 0.0
## Whether it heals by itself right now (the regeneration skill).
var regenerating: bool = false

## Seconds since the last damage (for regeneration).
var _since_damage: float = INF
## What brought the holder down, for the statistics once it dies.
var _downed_by: Node
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


## Loses `amount` health (from an attacker at `from`, if it has one) to `cause` (what dealt it, for
## the statistics); dies at zero.
func damage(amount: float, from: Vector3 = Vector3.INF, cause: Node = null) -> void:
	if life != Life.ALIVE or amount <= 0.0:
		return
	if god_mode:
		hurt.emit(amount, from)
		light.flash()
		return
	_since_damage = 0.0
	var lost: float = minf(amount, health)
	_set_health(health - amount)
	hurt.emit(amount, from)
	GameEvents.bus.player_hurt.emit(holder, lost, cause)
	if health > 0.0:
		light.flash()
		return
	regenerating = false
	light.regenerating = false
	if bleed_out > 0.0:
		life = Life.DOWN
		bleed_out_left = bleed_out
		_downed_by = cause
		went_down.emit()
	else:
		_die(cause)


## Restores `amount` health, all of it by default (only standing).
func heal(amount: float = INF) -> void:
	if life == Life.ALIVE:
		var before: float = health
		_set_health(minf(health + amount, maximum()))
		_report_healed(before)


## Sets the health to `value`, up to the maximum (only standing): e.g. what a save kept.
func restore(value: float) -> void:
	if life == Life.ALIVE:
		_set_health(minf(value, maximum()))


## Alive again with full health (from any state).
func revive() -> void:
	life = Life.ALIVE
	_set_health(maximum())


## A downed holder stands up again with `share` of its maximum health. Returns whether it was down.
func get_up(share: float) -> bool:
	if life != Life.DOWN:
		return false
	life = Life.ALIVE
	_set_health(maximum() * share)
	got_up.emit()
	return true


## A new maximum (armor or skills, bought aboard) adds the difference to the health.
func update_maximum() -> void:
	if life == Life.ALIVE:
		_set_health(health + maximum() - _maximum)


## Heals by itself with the regeneration skill, once it took no damage for a while; a downed
## holder bleeds out.
func update(delta: float) -> void:
	if life == Life.DOWN:
		bleed_out_left = maxf(bleed_out_left - delta, 0.0)
		if bleed_out_left == 0.0:
			_die(_downed_by if is_instance_valid(_downed_by) else null)
		return
	_since_damage += delta
	var rate: float = holder.skills.value(Skill.Effect.REGENERATION)
	regenerating = (
		life == Life.ALIVE
		and health < maximum()
		and _since_damage >= holder.settings.regeneration_delay
		and rate > 0.0
	)
	light.regenerating = regenerating
	if regenerating:
		var before: float = health
		_set_health(health + rate * delta)
		_report_healed(before)


func _die(cause: Node) -> void:
	life = Life.DEAD
	_downed_by = null
	died.emit()
	GameEvents.bus.player_died.emit(holder, cause)


func _report_healed(before: float) -> void:
	if health > before:
		GameEvents.bus.player_healed.emit(holder, health - before)


func _set_health(value: float) -> void:
	_maximum = maximum()
	health = clampf(value, 0.0, _maximum)
	light.show_health(health / _maximum)
	changed.emit(health)
