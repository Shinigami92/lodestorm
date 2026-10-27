class_name SoundList
extends GridContainer
## The sound settings, a page of their own next to the other settings (`SettingsList`, on the pause
## panel and the settings terminal in cabin 1, see docs/design/sound.md): a volume per sound bus
## (`Sfx.BUSES`, a slider in 10 % steps), each saved at once (see `GameSettings`). Moving one plays
## a sample on its bus.

## What a volume slider plays when it changes: a shot on the Master and Effects buses, the storm
## on the Ambience bus (once at a time); the Voice bus plays `VoiceLines.SAMPLE_LINE`.
const SHOT: Sound = preload("res://assets/audio/sfx/weapons/harl_shot.tres")
const SAMPLES: Dictionary[StringName, Sound] = {
	&"Master": SHOT,
	&"Effects": SHOT,
	&"Ambience": preload("res://assets/audio/sfx/mission/storm.tres"),
}

## Plays the voice sample (one at a time: the next one replaces it).
var _voice_sample: AudioStreamPlayer


func _ready() -> void:
	_voice_sample = VoiceLines.sample_player(self)
	for bus: StringName in Sfx.BUSES:
		var row := get_node("%" + bus) as HBoxContainer
		var slider := row.get_node(^"Slider") as HSlider
		slider.value = GameSettings.volume(bus)
		_show_volume(row, slider.value)
		slider.value_changed.connect(_on_volume_changed.bind(bus, row))


func _on_volume_changed(level: float, bus: StringName, row: HBoxContainer) -> void:
	GameSettings.set_volume(bus, level)
	_show_volume(row, level)
	if bus in SAMPLES:
		Sfx.play_ui(SAMPLES[bus], bus)
	elif bus == &"Voice":
		VoiceLines.play_sample(_voice_sample)


static func _show_volume(row: HBoxContainer, level: float) -> void:
	(row.get_node(^"Value") as Label).text = "%d %%" % roundi(level * 100.0)
