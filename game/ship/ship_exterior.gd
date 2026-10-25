class_name ShipExterior
extends Node3D
## The hull's model around the rooms (`assets/ship/ship_exterior.glb`, built by
## `assets/ship/source/ship_exterior_build.py`; blockout until the art pass's details): seen from
## outside, only casting shadows while the viewer is aboard (`Ship`). Its six legs (`Leg1`..`Leg6`)
## stand on the ground while landed; they come down in the touchdown's last `leg_time` seconds and
## pull up into their housings at the take-off, so in space, in flight and docked they're up.

## How far each leg pulls up (m). Matches the build script's `LEG_RETRACT`.
const LEG_RETRACT: float = 1.5

## Seconds the legs take to come down or go up. TBD (playtest).
@export var leg_time: float = 2.5
## The ship's flight, whose phase moves the legs.
@export var flight: ShipFlight

## How far the legs are down, from 0 (up) to 1 (on the ground).
var legs_down: float = 0.0

var _legs: Array[Node3D] = []
var _leg_rest: Array[float] = []


func _ready() -> void:
	for i: int in range(1, 7):
		var leg := find_child("Leg%d" % i) as Node3D
		if leg:
			_legs.append(leg)
			_leg_rest.append(leg.position.y)
	legs_down = _target()
	_place_legs()


func _process(delta: float) -> void:
	var target: float = _target()
	if legs_down == target:
		return
	legs_down = move_toward(legs_down, target, delta / leg_time)
	_place_legs()


## Where the legs should be: down while landed and at the end of the touchdown, else up.
func _target() -> float:
	if not flight:
		return 0.0
	match flight.phase:
		ShipFlight.Phase.LANDED:
			return 1.0
		ShipFlight.Phase.TOUCHDOWN:
			return 1.0 if flight.phase_duration() - flight.phase_time <= leg_time else 0.0
	return 0.0


func _place_legs() -> void:
	var up: float = (1.0 - legs_down) * LEG_RETRACT
	for i: int in _legs.size():
		_legs[i].position.y = _leg_rest[i] + up
