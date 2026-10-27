class_name MissionSounds
extends Node
## The mission's sounds for the local player (`viewer`), made by the `Weather` (see
## docs/design/sound.md): the storm's warning when the last part of the timer starts (a critical
## cue), the suit counting down the last minute (`BEEPS`), the storm hitting when the time is up,
## and the storm itself all around on the Ambience bus (a loop, as loud as `weather.intensity`,
## muffled aboard).

## The seconds left at which the suit beeps. TBD (playtest).
const BEEPS: Array[float] = [
	60.0, 50.0, 40.0, 30.0, 20.0, 10.0, 9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0
]
## How loud the storm still is aboard (a share). TBD (playtest).
const STORM_INDOORS: float = 0.3

const BEEP_SOUND: Sound = preload("res://assets/audio/sfx/mission/countdown_beep.tres")
const WARNING_SOUND: Sound = preload("res://assets/audio/sfx/mission/storm_warning.tres")
const STORM_SOUND: Sound = preload("res://assets/audio/sfx/mission/storm.tres")
const STORM_HIT_SOUND: Sound = preload("res://assets/audio/sfx/mission/storm_hit.tres")

var weather: Weather

## The seconds left on the last frame (INF: no run).
var _time_left: float = INF
var _storm: AudioStreamPlayer


func _ready() -> void:
	weather.mission.time_up.connect(_play.bind(STORM_HIT_SOUND, false))


func _process(_delta: float) -> void:
	var mission: Mission = weather.mission
	if mission.state == Mission.State.RUNNING:
		var now: float = mission.time_left
		if _crossed(mission.warning_time(), now):
			_play(WARNING_SOUND, true)
		for mark: float in BEEPS:
			if _crossed(mark, now):
				_play(BEEP_SOUND, false)
		_time_left = now
	else:
		_time_left = INF
	_update_storm()


## Whether the timer just went from above `mark` to it or below (`now`).
func _crossed(mark: float, now: float) -> bool:
	return _time_left > mark and now <= mark and _time_left < INF


func _update_storm() -> void:
	var level: float = weather.intensity * lerpf(1.0, STORM_INDOORS, weather.indoors)
	if level <= 0.001:
		Sfx.stop_loop(_storm)
		_storm = null
		return
	if not _storm:
		_storm = Sfx.play_loop(STORM_SOUND, self)
	_storm.volume_db = STORM_SOUND.volume_db + linear_to_db(level)


func _play(sound: Sound, critical: bool) -> void:
	if weather.viewer and weather.viewer.is_inside_tree():
		Sfx.play_at(sound, weather.viewer.global_position, critical)
