class_name GroundContact
extends RefCounted
## The ground hazards (`GroundHazard`) a player or alien stands in, and what they do to its
## movement, and a snare holding it back for a while (a stalker's hooks). Its owner keeps it as
## `ground_contact` and counts the snare down (`tick`).

var _hazards: Array[GroundHazard] = []
## The snare's share of the walking speed, and its seconds left.
var _snare: float = 1.0
var _snare_left: float = 0.0


## The contact of `body`, or null when it has none.
static func of(body: Node) -> GroundContact:
	return body.get(&"ground_contact") as GroundContact


func enter(hazard: GroundHazard) -> void:
	if hazard not in _hazards:
		_hazards.append(hazard)


func leave(hazard: GroundHazard) -> void:
	_hazards.erase(hazard)


## The share of the usual acceleration the feet have: the least grip of the hazards it stands in,
## 1 on ordinary ground.
func grip() -> float:
	var least: float = 1.0
	for hazard: GroundHazard in _hazards:
		least = minf(least, hazard.grip)
	return least


## Holds it to `share` of its walking speed for `seconds` (a stalker's hooks); a stronger snare
## under way stays, an equal one lasts the longer of the two.
func snare(share: float, seconds: float) -> void:
	if share < _snare or _snare_left == 0.0:
		_snare = share
		_snare_left = seconds
	elif share == _snare:
		_snare_left = maxf(_snare_left, seconds)


## Whether a snare holds it.
func is_snared() -> bool:
	return _snare_left > 0.0


## Counts the snare down.
func tick(delta: float) -> void:
	_snare_left = maxf(_snare_left - delta, 0.0)
	if _snare_left == 0.0:
		_snare = 1.0


## The share of the usual walking speed: the slowest of the hazards it stands in and its snare, 1 on
## ordinary ground.
func speed() -> float:
	var least: float = _snare
	for hazard: GroundHazard in _hazards:
		least = minf(least, hazard.speed)
	return least
