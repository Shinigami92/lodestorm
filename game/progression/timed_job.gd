class_name TimedJob
extends RefCounted
## An upgrade level or a skill rank under way (see `Upgrades.jobs`, `Skills.jobs`): it reaches
## `level` once `seconds` have passed since `started` on the wall clock (Unix seconds), also during
## runs and while the game is closed. Its time is kept as it was when it started, so retuning the
## data doesn't shift a running job. A clock set back makes it wait, never undoes it.

## The MK level or rank it reaches.
var level: int = 1
## When it started, in Unix seconds.
var started: float = 0.0
## How long it takes, in seconds.
var seconds: float = 0.0


func _init(to_level: int = 1, start_time: float = 0.0, duration: float = 0.0) -> void:
	level = to_level
	started = start_time
	seconds = duration


## Whether it's done at `now` (Unix seconds).
func is_done(now: float) -> bool:
	return now >= started + seconds


## How far it is at `now`, 0–1.
func progress(now: float) -> float:
	return clampf((now - started) / seconds, 0.0, 1.0) if seconds > 0.0 else 1.0


## Seconds until it's done, at `now`.
func time_left(now: float) -> float:
	return clampf(started + seconds - now, 0.0, seconds)
