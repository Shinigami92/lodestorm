class_name Message
extends Resource
## A short voiced message left for the ship while it's away (see docs/design/story.md, Between
## missions): it comes in on a return once the story flags it `requires` are set (usually a beat's
## flag, so the story director puts it out) and stays on the quest board's Messages tab to be heard
## again. Heard to the end once, its flag (`flag`) is set for the ship. A call from someone waiting
## at a station is one too, made from their `NpcProfile.calls` (see `MessageLog`).

## Who it is in the story's flags (`message.<id>`): saved, so it never changes; empty for a call.
@export var id: StringName
## Who leaves it: their `NpcProfile.id`.
@export var from: StringName
## What they say, one after another (the English texts, translated).
@export var lines: Array[String] = []
## Story flags it needs before it comes in (e.g. a beat's).
@export var requires: Array[StringName] = []


## Its story flag, set once it's heard to the end: `message.<id>`.
func flag() -> StringName:
	return StringName("message.%s" % id)


## Every line said in it, by who says it (see `VoiceLines.SPEAKING`): its `lines`, by `from`.
func spoken_lines() -> Dictionary[StringName, PackedStringArray]:
	var said: Dictionary[StringName, PackedStringArray] = {from: PackedStringArray(lines)}
	return said
