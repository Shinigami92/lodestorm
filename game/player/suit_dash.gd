class_name SuitDash
extends Node
## The dash (a skill): a short burst along the direction the player moves (else where they aim),
## then a cooldown. A weapon's lunge (Riven) moves the player the same way, without the skill or a
## cooldown (`lunge`). The `holder` asks it for its velocity every physics step (`step`). Distance,
## time and cooldown are in `PlayerSettings`.

## Emitted when a dash starts.
signal dashed

## The player dashing.
var holder: Player
## Seconds until the next dash (0: ready).
var cooldown: float = 0.0

## Seconds left of the dash underway, and its velocity.
var _left: float = 0.0
var _velocity: Vector3 = Vector3.ZERO


## Dashes along `direction` (horizontal; zero: where the holder aims) if the holder learned the
## dash, stands on the ground and the dash is ready. Returns whether it dashed.
func dash(direction: Vector3 = Vector3.ZERO) -> bool:
	if not holder or holder.dead or cooldown > 0.0 or not holder.is_on_floor():
		return false
	if not holder.skills.has(Skill.Effect.DASH):
		return false
	direction.y = 0.0
	if direction.length() < 0.01:
		direction = holder.aim.direction
	var settings: PlayerSettings = holder.settings
	_velocity = direction.normalized() * settings.dash_distance / settings.dash_time
	_left = settings.dash_time
	cooldown = settings.dash_cooldown
	dashed.emit()
	return true


## Darts the holder `distance` m along `direction` (horizontal) within `seconds` (a weapon's
## lunge): like a dash, but it needs no skill, doesn't wait for or start the cooldown and makes no
## sound of its own.
func lunge(direction: Vector3, distance: float, seconds: float) -> void:
	if not holder or holder.dead or distance <= 0.0 or seconds <= 0.0:
		return
	direction.y = 0.0
	_velocity = direction.normalized() * distance / seconds
	_left = seconds


## Whether a dash is underway.
func is_dashing() -> bool:
	return _left > 0.0


## How far the cooldown is (1: ready).
func ready_ratio() -> float:
	return 1.0 - cooldown / holder.settings.dash_cooldown if holder else 1.0


## The horizontal velocity for this physics step: the dash's while one is underway (at its end,
## carrying on at `speed` at most), else `walking`. Counts the cooldown down.
func step(walking: Vector3, speed: float, delta: float) -> Vector3:
	cooldown = maxf(cooldown - delta, 0.0)
	if _left <= 0.0:
		return walking
	_left -= delta
	if _left <= 0.0:
		return _velocity.normalized() * minf(speed, _velocity.length())
	return _velocity


## Stops a dash underway (e.g. on death); the cooldown goes on.
func cancel() -> void:
	_left = 0.0
