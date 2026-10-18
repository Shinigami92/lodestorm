class_name GroundContact
extends RefCounted
## The ground hazards (`GroundHazard`) a player or alien stands in, and what they do to its
## movement. Its owner keeps it as `ground_contact`.

var _hazards: Array[GroundHazard] = []


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


## The share of the usual walking speed: the slowest of the hazards it stands in, 1 on ordinary
## ground.
func speed() -> float:
	var least: float = 1.0
	for hazard: GroundHazard in _hazards:
		least = minf(least, hazard.speed)
	return least
