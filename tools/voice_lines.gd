extends SceneTree
## Writes who says which line, as the game finds them (`VoiceLines.lines_by_speaker`), for the
## voice tools (`tools/voice/lines.py` runs it): `-- --out=<file>`, JSON
## `{npc id: {"name", "role", "lines"}}` (the English lines in the game's order; name and role from
## their `NpcProfile`). A script run with `-s` compiles before the autoloads exist, and
## `VoiceLines` refers to them, so this names no game class: it loads `VoiceLines` once the tree
## runs. Quits with 1 when the game's code doesn't load or a line's speaker has no profile.

const VOICE_LINES: String = "res://game/npcs/voice_lines.gd"


func _initialize() -> void:
	var out: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	_write.call_deferred(out)


func _write(out: String) -> void:
	var voice_lines: GDScript = load(VOICE_LINES)
	if not voice_lines or not voice_lines.can_instantiate():
		push_error("%s doesn't load" % VOICE_LINES)
		quit(1)
		return
	var resources: Array[Resource] = voice_lines.call(&"speaking_resources")
	var by_speaker: Dictionary = voice_lines.call(&"lines_by_speaker", resources)
	var profiles: Dictionary[StringName, Resource] = {}
	for resource: Resource in resources:
		var script: Script = resource.get_script()
		if script.get_global_name() == &"NpcProfile":
			profiles[resource.get(&"id") as StringName] = resource
	var speakers: Dictionary = {}
	var failed: bool = out.is_empty()
	for speaker: StringName in by_speaker:
		var profile: Resource = profiles.get(speaker)
		if not profile:
			push_error("%s says lines but has no NpcProfile" % speaker)
			failed = true
			continue
		var lines: PackedStringArray = by_speaker[speaker]
		speakers[speaker] = {
			"name": profile.get(&"display_name"), "role": profile.get(&"role"), "lines": lines
		}
	if out.is_empty():
		push_error("Usage: tools/voice_lines.gd -- --out=<file>")
	else:
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(speakers, "\t", false) + "\n")
		file.close()
	quit(1 if failed else 0)
