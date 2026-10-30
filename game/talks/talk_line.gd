class_name TalkLine
extends Resource
## One line of an `OverheardTalk`: who says it and what.

## Who says it: their `NpcProfile.id`.
@export var npc: StringName
## What they say (the English text, translated).
@export var text: String = ""
