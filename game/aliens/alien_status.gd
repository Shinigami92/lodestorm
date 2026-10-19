class_name AlienStatus
extends RefCounted
## What the hive and other aliens do to an alien right now (`Alien.status`): a shrieker's boost,
## the hive's frenzy, a tender's link and its nest calling its guards. Values TBD (playtest).

## How much faster the hive makes it (its frenzy at the end of a run, set by its nest).
var hive_speed: float = 1.0
## Armor on every side on top of its strain's while a tender's link hardens it (see `MendLinks`),
## and that link's holder.
var bonus_armor: float = 0.0
var mended_by: Node
## The player who hit its nest (set by the nest on its guards, see `AlienNest`): a guard goes for
## them from any distance while they're within its leash. Null: none, or forgotten.
var defending: Node3D

## A scream's boost: how much faster it is, and for how many more seconds.
var _boost: float = 1.0
var _boost_left: float = 0.0


## Makes it `factor` times faster for `seconds` (a shrieker's scream); a stronger boost under way
## stays, an equal one lasts the longer of the two.
func boost(factor: float, seconds: float) -> void:
	if factor > _boost:
		_boost = factor
		_boost_left = seconds
	elif factor == _boost:
		_boost_left = maxf(_boost_left, seconds)


## Whether a scream's boost is under way.
func is_boosted() -> bool:
	return _boost_left > 0.0


## Whether it's faster than its strain right now (a boost, the frenzy): its eyes glow brighter.
func is_fast() -> bool:
	return is_boosted() or hive_speed > 1.0


## How much faster than its strain it is.
func speed() -> float:
	return _boost * hive_speed


## Whether a scream boosts it or a tender's link holds it: it's bigger and outlined then.
func is_buffed() -> bool:
	return is_boosted() or is_mended()


## Whether a tender's link holds it.
func is_mended() -> bool:
	return is_instance_valid(mended_by)


## Counts the boost down.
func tick(delta: float) -> void:
	_boost_left = maxf(_boost_left - delta, 0.0)
	if _boost_left == 0.0:
		_boost = 1.0
