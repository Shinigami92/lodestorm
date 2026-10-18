class_name AlienPose
extends RefCounted
## Moves an alien's body (the node holding its model) on top of its clips, until the models get
## their own clips: crouching for a wind-up, arcing through a leap, rearing up when staggered and
## a small jolt per hit. Values TBD (playtest).

## How low the body drops when fully crouched (m), and how far its nose dips (radians).
const CROUCH_DROP: float = 0.14
const CROUCH_PITCH: float = 0.12
## How far the nose rears up at the start of a stagger, and on a hit (radians).
const STAGGER_PITCH: float = -0.45
const JOLT_PITCH: float = -0.12
## Seconds a hit's jolt lasts.
const JOLT_TIME: float = 0.15
## How fast the crouch follows (higher = snappier).
const CROUCH_SPEED: float = 20.0

## 0 (standing) to 1 (fully crouched): where the crouch is going.
var crouch: float = 0.0
## Height of the leap's arc at its middle (m), and how far through it the body is (0 to 1).
var leap_height: float = 0.0
var leap: float = 0.0
## Seconds of stagger left, out of `stagger_time`.
var stagger_left: float = 0.0
var stagger_time: float = 1.0

var _crouched: float = 0.0
var _jolt_left: float = 0.0


## Starts a hit's jolt.
func jolt() -> void:
	_jolt_left = JOLT_TIME


## Starts rearing up for `seconds`.
func stagger(seconds: float) -> void:
	stagger_time = seconds
	stagger_left = seconds


## How crouched the body is right now (0 to 1).
func crouched() -> float:
	return _crouched


## Advances by `delta` and returns the body's transform under the alien (the model faces +Z, the
## alien -Z, so the body is turned around).
func update(delta: float) -> Transform3D:
	_crouched = lerpf(_crouched, crouch, 1.0 - exp(-CROUCH_SPEED * delta))
	_jolt_left = maxf(_jolt_left - delta, 0.0)
	stagger_left = maxf(stagger_left - delta, 0.0)
	var height: float = -CROUCH_DROP * _crouched + 4.0 * leap_height * leap * (1.0 - leap)
	# Positive pitch dips the nose.
	var pitch: float = CROUCH_PITCH * _crouched
	pitch += JOLT_PITCH * _jolt_left / JOLT_TIME
	if stagger_left > 0.0:
		# Up fast, back down slowly.
		var t: float = 1.0 - stagger_left / stagger_time
		pitch += STAGGER_PITCH * minf(t * 5.0, 1.0) * (1.0 - t)
	var basis := Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, pitch)
	return Transform3D(basis, Vector3.UP * height)
