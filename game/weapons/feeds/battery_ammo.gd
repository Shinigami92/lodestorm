class_name BatteryAmmo
extends WeaponAmmo
## The ammo of a weapon fed by a battery (`BatteryFeed`): each attack uses one of its `rounds`; a
## full battery holds `capacity()` (more with the capacity's MK level). A while after the last shot
## it recharges by itself, for no ore. Run empty, it's drained (if its feed `drains`): it recharges
## fully before it fires again (a refill without a timing window). No spares, no reload by hand; a
## teammate can't hand it ammo. Sounds: an empty click when the trigger is pulled while drained, a
## chime when it's full again (one that doesn't drain: when a shot has recharged).

const EMPTY_SOUND: Sound = preload("res://assets/audio/sfx/weapons/empty_click.tres")

var feed: BatteryFeed

## How far the next round has recharged, 0 to 1.
var _partial: float = 0.0
## Seconds since the last shot.
var _idle: float = INF
var _drained: bool = false
var _trigger_was_held: bool = false


func _init(fed: Weapon, battery_feed: BatteryFeed) -> void:
	super(fed)
	feed = battery_feed


func capacity() -> int:
	return maxi(1, roundi(feed.cells * weapon.multiplier(WeaponPart.Stat.CAPACITY)))


func process(delta: float) -> void:
	_idle += delta
	var speed: float = weapon.multiplier(WeaponPart.Stat.RECHARGE)
	if _drained:
		_partial += delta * speed * capacity() / maxf(feed.drained_recharge_time, 0.01)
	elif _idle >= feed.recharge_delay:
		_partial += delta * speed * feed.recharge_rate
	var whole: int = floori(_partial)
	if whole > 0 and not feed.drains and rounds < capacity():
		weapon.play(feed.charged_sound)
	rounds = mini(rounds + whole, capacity())
	_partial = 0.0 if rounds >= capacity() else _partial - whole
	if _drained and rounds >= capacity():
		_drained = false
		weapon.play(feed.charged_sound)
	if weapon.trigger_held and not _trigger_was_held and _drained:
		weapon.play(EMPTY_SOUND)
	_trigger_was_held = weapon.trigger_held


func can_attack() -> bool:
	return rounds > 0 and not _drained


func use() -> void:
	rounds -= 1
	_idle = 0.0
	if rounds <= 0:
		rounds = 0
		_partial = 0.0
		_drained = feed.drains


func fill(_spare_magazines: int) -> void:
	rounds = capacity()
	_partial = 0.0
	_drained = false


func reload() -> bool:
	return false


func cancel_reload() -> void:
	pass


func receive_ammo(_giver: Player) -> bool:
	return false


func can_reload() -> bool:
	return true


func refilling() -> bool:
	return _drained


func refill_share() -> float:
	return (rounds + _partial) / capacity() if _drained else 0.0


func uses_spares() -> bool:
	return false
