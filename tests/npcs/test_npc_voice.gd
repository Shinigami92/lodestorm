extends GutTest
## The NPCs' voices (`VoiceLines`): every line of a voiced NPC has its recording in every voice
## language and no recording is left over, the quartermaster speaks the lines he shows, and the
## voice language setting (apart from the texts', or off).

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const SETTINGS_LIST: PackedScene = preload("res://game/ui/settings_list.tscn")
const SOUND_LIST: PackedScene = preload("res://game/ui/sound_list.tscn")
## The NPCs with recorded voices.
const VOICED: Array[NpcProfile] = [
	preload("res://game/npcs/crew/quartermaster.tres"),
	preload("res://game/npcs/ostra/bartender.tres"),
	preload("res://game/npcs/ostra/depot_master.tres"),
	preload("res://game/npcs/ostra/councillor.tres"),
	preload("res://game/npcs/crew/engineer.tres"),
	preload("res://game/npcs/crew/medic.tres"),
	preload("res://game/npcs/crew/gunsmith.tres"),
	preload("res://game/npcs/crew/suit_tech.tres"),
	preload("res://game/npcs/crew/miner_mechanic.tres"),
	preload("res://game/npcs/crew/pilot.tres"),
]
## The NPCs voiced only in English so far (in German, they speak English).
const VOICED_IN_ENGLISH: Array[NpcProfile] = [preload("res://game/npcs/crew/cook.tres")]
const DIRECTORY: String = "user://test_npc_voice/"

var _map: Node3D
var _player: Player
var _ship: Ship
var _npc: Npc


func before_each() -> void:
	GameSettings.voice_language = ""
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	_npc = _ship.get_node("Rooms/Lower/Armory/Quartermaster") as Npc
	await wait_physics_frames(2)


func after_each() -> void:
	GameSettings.voice_language = ""
	TranslationServer.set_locale("en")
	if SaveGame.directory:
		DirAccess.remove_absolute(GameSettings.path())
		SaveGame.directory = ""


func test_every_line_has_its_recording_in_every_voice_language() -> void:
	for profile: NpcProfile in VOICED:
		for language: String in VoiceLines.LANGUAGES:
			for line: String in _lines(profile):
				assert_true(
					ResourceLoader.exists(VoiceLines.path(profile.id, language, line)),
					"%s (%s): %s" % [profile.id, language, line]
				)
	for profile: NpcProfile in VOICED_IN_ENGLISH:
		for line: String in _lines(profile):
			assert_true(
				ResourceLoader.exists(VoiceLines.path(profile.id, "en", line)),
				"%s (en): %s" % [profile.id, line]
			)


func test_no_recording_is_left_over() -> void:
	for profile: NpcProfile in VOICED + VOICED_IN_ENGLISH:
		var keys: Array[String] = []
		for line: String in _lines(profile):
			keys.append(VoiceLines.path(profile.id, "en", line).get_file().get_basename())
		for language: String in VoiceLines.LANGUAGES:
			var folder: String = "%s/%s/%s" % [VoiceLines.ROOT, profile.id, language]
			if not DirAccess.dir_exists_absolute(folder):
				continue
			for file: String in DirAccess.get_files_at(folder):
				if file.get_extension() == "ogg":
					assert_has(
						keys, file.get_basename(), "%s/%s: no line any more" % [folder, file]
					)


func test_lines_are_spoken_as_they_show() -> void:
	await _talk()
	var greeting: Topic = _npc.profile.dialogue.greeting
	assert_eq(_npc.voice.bus, &"Voice")
	assert_eq(_recording(), VoiceLines.path(&"quartermaster", "en", greeting.lines[0]))
	_npc.press()
	assert_eq(_recording(), VoiceLines.path(&"quartermaster", "en", greeting.lines[1]))
	for i: int in greeting.lines.size() - 1:
		_npc.press()
	assert_false(_npc.voice.playing, "back at the list: nothing to say")
	_npc.close()
	assert_false(_npc.voice.playing)


func test_the_prompt_is_spoken_when_the_talk_starts_without_the_greeting() -> void:
	_ship.story.set_flag(_npc.profile.dialogue.greeting.id)
	await _talk()
	assert_eq(_recording(), VoiceLines.path(&"quartermaster", "en", _npc.profile.dialogue.prompt))


func test_the_voice_follows_the_texts_until_one_is_picked() -> void:
	TranslationServer.set_locale("de")
	assert_eq(VoiceLines.spoken_language(), "de")
	GameSettings.voice_language = "en"
	assert_eq(VoiceLines.spoken_language(), "en", "English voices with German texts")
	await _talk()
	var greeting: Topic = _npc.profile.dialogue.greeting
	assert_eq(_recording(), VoiceLines.path(&"quartermaster", "en", greeting.lines[0]))
	GameSettings.voice_language = "de"
	TranslationServer.set_locale("en")
	_npc.press()
	assert_eq(
		_recording(),
		VoiceLines.path(&"quartermaster", "de", greeting.lines[1]),
		"German voices with English texts"
	)


func test_voices_off_say_nothing() -> void:
	GameSettings.voice_language = VoiceLines.OFF
	assert_null(VoiceLines.stream(&"quartermaster", _npc.profile.dialogue.prompt))
	await _talk()
	assert_false(_npc.voice.playing)


func test_a_line_without_a_recording_stays_silent() -> void:
	assert_null(VoiceLines.stream(&"nobody", "Hello."))


func test_the_voice_language_is_picked_in_the_settings_and_saved() -> void:
	SaveGame.directory = DIRECTORY
	var list := SETTINGS_LIST.instantiate() as SettingsList
	add_child_autofree(list)
	var row := list.get_node("%VoiceLanguages") as HBoxContainer
	var names: Array[String] = []
	for button: Button in row.get_children():
		names.append(String(button.name))
	assert_eq(
		names, VoiceLines.LANGUAGES + [VoiceLines.OFF] as Array[String], "the languages, then off"
	)
	assert_true((row.get_node("en") as Button).button_pressed, "following the texts (English)")
	(row.get_node("de") as Button).pressed.emit()
	assert_eq(GameSettings.voice_language, "de")
	GameSettings.voice_language = ""
	GameSettings.load_settings()
	assert_eq(GameSettings.voice_language, "de", "saved")
	(row.get_node(VoiceLines.OFF) as Button).pressed.emit()
	assert_eq(VoiceLines.spoken_language(), "")


func test_each_pick_plays_the_sample_again() -> void:
	var list := SETTINGS_LIST.instantiate() as SettingsList
	add_child_autofree(list)
	var row := list.get_node("%VoiceLanguages") as HBoxContainer
	var sample := list.get_node("VoiceSample") as AudioStreamPlayer
	assert_eq(sample.bus, &"Voice")
	for code: String in ["de", "en", "de"]:
		(row.get_node(code) as Button).pressed.emit()
		var line: String = VoiceLines.SAMPLE_LINE
		assert_eq(sample.stream.resource_path, VoiceLines.path(VoiceLines.SAMPLE_NPC, code, line))
		# A sample that ended keeps its player (it used to free itself, and the next pick failed).
		sample.stop()
		sample.finished.emit()
		await wait_process_frames(1)
		assert_true(is_instance_valid(sample), code)


func test_voices_have_their_own_volume() -> void:
	assert_has(Sfx.BUSES, &"Voice")
	assert_gt(AudioServer.get_bus_index(&"Voice"), 0)
	var list := SOUND_LIST.instantiate() as SoundList
	add_child_autofree(list)
	var row := list.get_node("%Voice") as HBoxContainer
	(row.get_node(^"Slider") as HSlider).value = 0.4
	assert_almost_eq(GameSettings.volume(&"Voice"), 0.4, 0.001)
	GameSettings.volumes.clear()


## The English lines of `profile`: the prompt, the greeting's and every topic's.
func _lines(profile: NpcProfile) -> Array[String]:
	var lines: Array[String] = []
	lines.append(profile.dialogue.prompt)
	for topic: Topic in [profile.dialogue.greeting] + profile.dialogue.topics:
		lines.append_array(topic.lines)
	for reaction: CrewReaction in profile.reactions:
		lines.append_array(reaction.lines)
	return lines


## The file of the recording the NPC plays.
func _recording() -> String:
	return _npc.voice.stream.resource_path if _npc.voice.stream else ""


func _talk() -> void:
	_player.global_position = _npc.use_point.global_position + Vector3(0.0, 0.0, 1.0)
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	_npc.use_point.use(_player)
	await wait_process_frames(1)
