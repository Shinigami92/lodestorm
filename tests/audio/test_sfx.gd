extends GutTest

const SETTINGS_LIST: PackedScene = preload("res://game/ui/settings_list.tscn")
const SHOT: Sound = preload("res://assets/audio/sfx/weapons/blaster_shot.tres")
const TICK: Sound = preload("res://assets/audio/sfx/weapons/window_tick.tres")
const DRILL: Sound = preload("res://assets/audio/sfx/mining/drill.tres")
const DIRECTORY: String = "user://test_sfx/"

var _ears: AudioListener3D
var _played: Array[Sound] = []


func before_each() -> void:
	Sfx.stop_all()
	_ears = AudioListener3D.new()
	add_child_autofree(_ears)
	_ears.make_current()
	_played.clear()
	Sfx.played.connect(_on_played)


func after_each() -> void:
	Sfx.played.disconnect(_on_played)
	Sfx.stop_all()
	GameSettings.volumes.clear()
	SaveGame.directory = ""


func test_beyond_its_limit_the_farthest_sound_is_dropped() -> void:
	for index: int in SHOT.limit:
		assert_not_null(Sfx.play_at(SHOT, Vector3(10.0 + index, 0.0, 0.0)))
	assert_eq(Sfx.playing(SHOT), SHOT.limit)
	assert_null(Sfx.play_at(SHOT, Vector3(30.0, 0.0, 0.0)), "farther than every one playing")
	var farthest: Node = Sfx.get_children()[-1]
	assert_not_null(Sfx.play_at(SHOT, Vector3(1.0, 0.0, 0.0)), "nearer: the farthest makes room")
	assert_eq(Sfx.playing(SHOT), SHOT.limit)
	assert_true(farthest.is_queued_for_deletion())


func test_a_lower_pitch_plays_longer() -> void:
	Sfx.play_at(SHOT, Vector3.ZERO, false, 0.5)
	await wait_seconds(SHOT.length() * 1.2)
	assert_eq(Sfx.playing(SHOT), 1, "half the pitch: twice as long")
	await wait_seconds(SHOT.length() * 1.0)
	assert_eq(Sfx.playing(SHOT), 0)


func test_a_loop_follows_its_holder_until_stopped() -> void:
	var holder := Node3D.new()
	add_child_autofree(holder)
	var loop: AudioStreamPlayer3D = Sfx.play_loop_at(DRILL, holder)
	assert_eq(loop.get_parent(), holder)
	assert_true(loop.playing)
	assert_has(_played, DRILL)
	var wav := (DRILL.stream as AudioStreamRandomizer).get_stream(0) as AudioStreamWAV
	assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD, "its loop points come with the file")
	await wait_seconds(DRILL.length() * 1.5)
	assert_true(is_instance_valid(loop) and not loop.is_queued_for_deletion(), "loops go on")
	Sfx.stop_loop(loop)
	assert_true(loop.is_queued_for_deletion())


func test_sounds_are_done_after_their_length() -> void:
	var player := Sfx.play_at(SHOT, Vector3.ZERO)
	assert_eq(Sfx.playing(SHOT), 1)
	assert_eq(_played, [SHOT] as Array[Sound])
	await wait_seconds(SHOT.length() + 0.1)
	assert_eq(Sfx.playing(SHOT), 0)
	assert_false(is_instance_valid(player))


func test_critical_cues_always_play_and_duck_the_rest() -> void:
	var effects: int = AudioServer.get_bus_index(&"Effects")
	var master: int = AudioServer.get_bus_index(&"Master")
	assert_not_null(Sfx.play_at(TICK, Vector3.ZERO))
	assert_null(Sfx.play_at(TICK, Vector3.ZERO), "its limit is one")
	assert_not_null(Sfx.play_at(TICK, Vector3(5.0, 0.0, 0.0), true))
	await wait_process_frames(2)
	assert_almost_eq(AudioServer.get_bus_volume_db(effects), Sfx.DUCK_DB, 0.01)
	assert_almost_eq(AudioServer.get_bus_volume_db(master), 0.0, 0.01, "the cue itself isn't")
	await wait_seconds(TICK.length() + Sfx.DUCK_RELEASE + 0.1)
	assert_almost_eq(AudioServer.get_bus_volume_db(effects), 0.0, 0.01)


func test_volumes_follow_the_settings_and_are_saved() -> void:
	SaveGame.directory = DIRECTORY
	var effects: int = AudioServer.get_bus_index(&"Effects")
	GameSettings.set_volume(&"Effects", 0.5)
	GameSettings.set_volume(&"Ambience", 0.0)
	await wait_process_frames(2)
	assert_almost_eq(AudioServer.get_bus_volume_db(effects), linear_to_db(0.5), 0.01)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Ambience")))
	GameSettings.volumes.clear()
	GameSettings.load_settings()
	assert_almost_eq(GameSettings.volume(&"Effects"), 0.5, 0.001)
	assert_eq(GameSettings.volume(&"Ambience"), 0.0)
	assert_eq(GameSettings.volume(&"Master"), 1.0, "unchanged: full volume")
	DirAccess.remove_absolute(GameSettings.path())
	DirAccess.remove_absolute(DIRECTORY)


func test_a_volume_slider_sets_its_bus_and_plays_a_sample() -> void:
	var list := SETTINGS_LIST.instantiate() as SettingsList
	add_child_autofree(list)
	var row := list.get_node("%Effects") as HBoxContainer
	(row.get_node(^"Slider") as HSlider).value = 0.3
	assert_almost_eq(GameSettings.volume(&"Effects"), 0.3, 0.001)
	assert_eq((row.get_node(^"Value") as Label).text, "30 %")
	assert_eq(_played, [SHOT] as Array[Sound])


func _on_played(sound: Sound, _critical: bool) -> void:
	_played.append(sound)
