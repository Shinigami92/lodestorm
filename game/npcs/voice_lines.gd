class_name VoiceLines
extends RefCounted
## The NPCs' recorded voices (see docs/design/localization-and-voice.md): one Ogg file per line
## and voice language in `assets/voice/<npc id>/<language>/`, named by the first 16 hex digits of
## the SHA-256 of the English line (its translation key), as `tools/voice.sh` renders them. Which
## language they speak is a setting of its own (`GameSettings.voice_language`), apart from the
## texts' language; a line without a recording in it falls back to English, one without any stays
## silent.

const ROOT: String = "res://assets/voice"
## The voice languages with rendered lines, English first. A language is listed (and shows in the
## settings) once its lines are rendered.
const LANGUAGES: Array[String] = ["en", "de"]
## The voice language setting for no voices at all.
const OFF: String = "off"
## What the settings play as a sample of the voices: the quartermaster's prompt (English).
const SAMPLE_NPC: StringName = &"quartermaster"
const SAMPLE_LINE: String = "How can I help you?"


## Where the recording of `line` (the English text) by `npc` (its `NpcProfile.id`) in `language`
## is, whether it exists or not.
static func path(npc: StringName, language: String, line: String) -> String:
	return "%s/%s/%s/%s.ogg" % [ROOT, npc, language, line.sha256_text().left(16)]


## The language the NPCs speak now: the one picked in the settings, else the texts' language when
## it has voices, else English; empty with voices off.
static func spoken_language() -> String:
	var picked: String = GameSettings.voice_language
	if picked == OFF:
		return ""
	if picked in LANGUAGES:
		return picked
	var text: String = SettingsList.current_language()
	return text if text in LANGUAGES else LANGUAGES[0]


## The recording of `line` (English) by `npc` in the voice language, else in English; null without
## one or with voices off.
static func stream(npc: StringName, line: String) -> AudioStream:
	var spoken: String = spoken_language()
	if not spoken or line.is_empty():
		return null
	for code: String in [spoken, LANGUAGES[0]]:
		var file: String = path(npc, code, line)
		if ResourceLoader.exists(file):
			return load(file) as AudioStream
	return null


## Plays `SAMPLE_LINE` by `SAMPLE_NPC` in the voice language on `player` (flat, see
## `sample_player`), from the start; just stops it without a recording (or with voices off).
static func play_sample(player: AudioStreamPlayer) -> void:
	player.stop()
	var recording: AudioStream = stream(SAMPLE_NPC, SAMPLE_LINE)
	if recording:
		player.stream = recording
		player.play()


## A player for `play_sample` under `holder`: on the Voice bus, also while the game is paused.
static func sample_player(holder: Node) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = "VoiceSample"
	player.bus = &"Voice"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	holder.add_child(player)
	return player
