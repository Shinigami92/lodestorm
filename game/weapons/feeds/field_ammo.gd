class_name FieldAmmo
extends WeaponAmmo
## The charge of a shield's field (`FieldFeed`, Mantle), as its `rounds`: the damage it can still
## stop, `capacity()` when full (more with the MK level of the weapon's capacity). Each block drains
## it by the damage stopped (`absorb`); a while after the last block it recharges by itself. A hit
## bigger than what's left goes through with the rest and breaks it: it's down for the feed's
## break time (`refilling`), then back full. No ore, no reload, no spares, and a teammate can't
## hand it any; the weapon bashes whatever its charge.

var feed: FieldFeed

var _charge: float = 0.0
## Seconds since the last block.
var _idle: float = INF
## Seconds a broken field stays down.
var _broken_left: float = 0.0


func _init(fed: Weapon, field_feed: FieldFeed) -> void:
	super(fed)
	feed = field_feed


func capacity() -> int:
	return maxi(1, roundi(feed.charge * weapon.multiplier(WeaponPart.Stat.CAPACITY)))


func process(delta: float) -> void:
	_sync()
	if _broken_left > 0.0:
		_broken_left -= delta
		if _broken_left <= 0.0:
			_broken_left = 0.0
			_set_charge(capacity())
			weapon.play(feed.back_sound)
		return
	_idle += delta
	if _idle >= feed.recharge_delay and _charge < capacity():
		_set_charge(minf(_charge + feed.recharge_rate * delta, capacity()))


## Stops `amount` damage: drains the charge by it. Returns the damage that gets through: none while
## the charge holds, the rest when it breaks the field, all of it while it's broken.
func absorb(amount: float) -> float:
	_sync()
	if is_broken() or amount <= 0.0:
		return maxf(amount, 0.0)
	_idle = 0.0
	if amount < _charge:
		_set_charge(_charge - amount)
		return 0.0
	var through: float = amount - _charge
	_set_charge(0.0)
	_broken_left = feed.break_time
	weapon.play(feed.break_sound)
	return through


## Whether the field is down after it broke.
func is_broken() -> bool:
	return _broken_left > 0.0


## The charge left, as a share of a full one.
func share() -> float:
	return _charge / capacity()


func can_attack() -> bool:
	return true


func use() -> void:
	pass


func fill(_spare_magazines: int) -> void:
	_broken_left = 0.0
	_idle = INF
	_set_charge(capacity())


func reload() -> bool:
	return false


func cancel_reload() -> void:
	pass


func receive_ammo(_giver: Player) -> bool:
	return false


func can_reload() -> bool:
	return true


func refilling() -> bool:
	return is_broken()


func refill_share() -> float:
	return 1.0 - _broken_left / maxf(feed.break_time, 0.01) if is_broken() else 0.0


func uses_spares() -> bool:
	return false


func upgraded() -> void:
	super()
	_charge = minf(_charge, capacity())


## Takes over `rounds` set from outside (the holder giving it its charge back on a switch).
func _sync() -> void:
	if rounds != ceili(_charge):
		_charge = float(rounds)


func _set_charge(value: float) -> void:
	_charge = value
	rounds = ceili(_charge)
