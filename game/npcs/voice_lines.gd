class_name VoiceLines
extends RefCounted
## The NPCs' recorded voices (see docs/design/localization-and-voice.md): one Ogg file per line
## and voice language in `assets/voice/<npc id>/<language>/`, named by the first 16 hex digits of
## the SHA-256 of the English line (its translation key), as `tools/voice.sh` renders them. Which
## language they speak is a setting of its own (`GameSettings.voice_language`), apart from the
## texts' language; a line without a recording in it falls back to English, one without any stays
## silent. A line said by itself (moving on in a talk, said aside, a radio call) stays for its
## `stay_time`.

const ROOT: String = "res://assets/voice"
## The voice languages with rendered lines, English first. A language is listed (and shows in the
## settings) once its lines are rendered.
const LANGUAGES: Array[String] = ["en", "de"]
## The voice language setting for no voices at all.
const OFF: String = "off"
## What the settings play as a sample of the voices: the quartermaster's prompt (English).
const SAMPLE_NPC: StringName = &"quartermaster"
const SAMPLE_LINE: String = "How can I help you?"
## How long a line stays: the pause after its voice ends, and without a voice `READ_BASE` s plus
## `READ_PER_LETTER` s per letter of the shown text (a calm reading speed), in s. TBD (playtest).
const AUTO_PAUSE: float = 1.0
const READ_BASE: float = 2.0
const READ_PER_LETTER: float = 0.06
## Resource types (script class names) whose files hold lines NPCs say, each with a
## `spoken_lines() -> Dictionary[StringName, PackedStringArray]` (who says them, their
## `NpcProfile.id`, to the English lines): a line can live in another file than its speaker's
## profile, e.g. a quest's hand-in said by the NPC it names.
const SPEAKING: Array[String] = ["NpcProfile", "Quest", "Message"]
## Where `speaking_resources` looks.
const SOURCE_DIR: String = "res://game"


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


## How long `text` (a shown line) stays without a voice, in s.
static func reading_time(text: String) -> float:
	return READ_BASE + READ_PER_LETTER * text.length()


## How long a line stays when it's said by itself: its `recording` and `AUTO_PAUSE`, else the
## `reading_time` of `text` (the shown line), in s.
static func stay_time(recording: AudioStream, text: String) -> float:
	return recording.get_length() + AUTO_PAUSE if recording else reading_time(text)


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


## Every resource under `dir` (and its folders) of a type in `SPEAKING`, in file order. Reads the
## text resources' headers (`.tres`), so it's for the tools and the tests, not an exported game.
static func speaking_resources(dir: String = SOURCE_DIR) -> Array[Resource]:
	var found: Array[Resource] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() != "tres":
			continue
		var file_path: String = dir.path_join(file)
		var header: String = FileAccess.open(file_path, FileAccess.READ).get_line()
		for type: String in SPEAKING:
			if 'script_class="%s"' % type in header:
				found.append(load(file_path))
				break
	for folder: String in DirAccess.get_directories_at(dir):
		found.append_array(speaking_resources(dir.path_join(folder)))
	return found


## Every line said in `resources` (see `SPEAKING`), by who says it (their `NpcProfile.id`), each
## once, in the order of `resources`: what's voiced (`tools/voice.sh` renders it).
static func lines_by_speaker(
	resources: Array[Resource]
) -> Dictionary[StringName, PackedStringArray]:
	var by_speaker: Dictionary[StringName, PackedStringArray] = {}
	for resource: Resource in resources:
		var said: Dictionary = resource.call(&"spoken_lines")
		for speaker: StringName in said:
			var lines: PackedStringArray = by_speaker.get(speaker, PackedStringArray())
			var spoken: PackedStringArray = said[speaker]
			for line: String in spoken:
				if line not in lines:
					lines.append(line)
			by_speaker[speaker] = lines
	return by_speaker
