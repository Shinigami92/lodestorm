extends GutTest
## Every game sound is listed in the manifest of `assets/audio/source/build.py` with how it was
## made (built by it, or a replacement: e.g. the AI model, "recorded") and the recordings it uses;
## every recording has its source, author and an allowed license (the game is sold: no NC, ND or
## SA). See TECHNICAL.md, Sound effects.

const MANIFEST: String = "res://assets/audio/source/manifest.json"
const RECORDINGS: String = "res://assets/audio/source/recordings/"
const SFX: String = "res://assets/audio/sfx/"
const ALLOWED_LICENSES: Array[String] = ["CC0-1.0", "CC-BY-4.0"]

var _manifest: Dictionary


func before_all() -> void:
	_manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))


func test_every_sound_file_is_in_the_manifest() -> void:
	var sounds: Dictionary = _manifest.sounds
	for path: String in _wav_files(SFX):
		var file: String = path.trim_prefix(SFX).get_basename()
		var sound: String = file.rsplit("_", true, 1)[0]
		var variant: int = file.rsplit("_", true, 1)[1].to_int()
		assert_has(sounds, sound, "%s is in the manifest" % path)
		if sound in sounds:
			var entry: Dictionary = sounds[sound]
			var variants: int = entry.variants
			assert_between(variant, 1, variants, "%s is one of its variants" % path)


func test_every_sound_in_the_manifest_is_built() -> void:
	for sound: String in _manifest.sounds:
		var entry: Dictionary = _manifest.sounds[sound]
		var made_by: String = entry.get("made_by", "")
		assert_ne(made_by, "", "%s says how it was made" % sound)
		var variants: int = entry.variants
		for variant: int in range(1, variants + 1):
			var path: String = "%s%s_%d.wav" % [SFX, sound, variant]
			assert_true(FileAccess.file_exists(path), "%s exists" % path)


func test_every_recording_used_has_an_allowed_license() -> void:
	assert_true(_manifest.recordings is Dictionary, "the manifest lists the recordings")
	var recordings: Dictionary = _manifest.recordings
	for sound: String in _manifest.sounds:
		var entry: Dictionary = _manifest.sounds[sound]
		for recording: String in entry.recordings:
			assert_has(recordings, recording, "%s: %s is in the manifest" % [sound, recording])
			if recording not in recordings:
				continue
			var source: Dictionary = recordings[recording]
			var license: String = source.get("license", "")
			assert_has(ALLOWED_LICENSES, license, "%s's license" % recording)
			assert_ne(str(source.get("source", "")), "", "%s's source URL" % recording)
			assert_ne(str(source.get("author", "")), "", "%s's author" % recording)
			assert_true(FileAccess.file_exists(RECORDINGS + recording), "%s is there" % recording)


func _wav_files(directory: String) -> PackedStringArray:
	var files := PackedStringArray()
	for file: String in DirAccess.get_files_at(directory):
		if file.get_extension() == "wav":
			files.append(directory + file)
	for sub: String in DirAccess.get_directories_at(directory):
		files.append_array(_wav_files(directory + sub + "/"))
	return files
