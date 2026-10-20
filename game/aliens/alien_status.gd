class_name AlienStatus
extends RefCounted
## What the hive, other aliens and players' weapons do to an alien right now (`Alien.status`): a
## shrieker's boost, the hive's frenzy, a tender's link, its nest calling its guards, a gravity
## well holding it and a weapon slowing it (a saw). Values TBD (playtest).

## Seconds a well's hold lasts after its last renewal (wells renew it every physics step).
const HOLD_GRACE: float = 0.1
## How fast an alien a well doesn't hold (the apex) moves while it's in one.
const WELL_SLOW: float = 0.5

## How much faster the hive makes it (its frenzy at the end of a run, set by its nest).
var hive_speed: float = 1.0
## Armor on every side on top of its strain's while a tender's link hardens it (see `MendLinks`),
## and that link's holder.
var bonus_armor: float = 0.0
var mended_by: Node
## The player who hit its nest (set by the nest on its guards, see `AlienNest`): a guard goes for
## them from any distance while they're within its leash. Null: none, or forgotten.
var defending: Node3D
## How fast a gravity well pulls it towards its middle (m/s, horizontal) while it's in one.
var pull := Vector3.ZERO

## A scream's boost: how much faster it is, and for how many more seconds.
var _boost: float = 1.0
var _boost_left: float = 0.0
var _held_left: float = 0.0
## A weapon's slow: the share of its speed it keeps, and for how many more seconds.
var _slow: float = 1.0
var _slow_left: float = 0.0


## Makes it `factor` times faster for `seconds` (a shrieker's scream); a stronger boost under way
## stays, an equal one lasts the longer of the two.
func boost(factor: float, seconds: float) -> void:
	if factor > _boost:
		_boost = factor
		_boost_left = seconds
	elif factor == _boost:
		_boost_left = maxf(_boost_left, seconds)


## Puts it in a gravity well pulling it at `velocity` (see `GravityWell`): an alien the wells hold
## (`AlienStrain.held_by_wells`) can't walk or start attacks that move it, and a flier sinks low;
## any other is slowed. A well renews it every physics step.
func hold(velocity: Vector3) -> void:
	pull = velocity
	_held_left = HOLD_GRACE


## Slows it to `factor` of its speed for `seconds` (a weapon's hit, see `SlowEffect`); a stronger
## slow under way stays, an equal one lasts the longer of the two.
func slow(factor: float, seconds: float) -> void:
	if factor < _slow:
		_slow = factor
		_slow_left = seconds
	elif factor == _slow:
		_slow_left = maxf(_slow_left, seconds)


## Whether a gravity well has it.
func is_held() -> bool:
	return _held_left > 0.0


## Whether a scream's boost is under way.
func is_boosted() -> bool:
	return _boost_left > 0.0


## Whether it's faster than its strain right now (a boost, the frenzy): its eyes glow brighter.
func is_fast() -> bool:
	return is_boosted() or hive_speed > 1.0


## How much faster than its strain it is.
func speed() -> float:
	return _boost * hive_speed * _slow * (WELL_SLOW if is_held() else 1.0)


## Whether a scream boosts it or a tender's link holds it: it's bigger and outlined then.
func is_buffed() -> bool:
	return is_boosted() or is_mended()


## Whether a tender's link holds it.
func is_mended() -> bool:
	return is_instance_valid(mended_by)


## Counts the boost, a well's hold and a slow down.
func tick(delta: float) -> void:
	_held_left = maxf(_held_left - delta, 0.0)
	if _held_left == 0.0:
		pull = Vector3.ZERO
	_boost_left = maxf(_boost_left - delta, 0.0)
	if _boost_left == 0.0:
		_boost = 1.0
	_slow_left = maxf(_slow_left - delta, 0.0)
	if _slow_left == 0.0:
		_slow = 1.0
