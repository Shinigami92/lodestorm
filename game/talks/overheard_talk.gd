class_name OverheardTalk
extends Resource
## Two NPCs talking to each other at a place, for whoever comes close (see docs/design/story.md,
## Between missions): once the story flags it `requires` are set (usually a beat's), both walk to
## its talk spot (a `TalkSpot` named `spot`, aboard or at a station) and wait there; the first
## player within `OverheardTalks.START_RANGE` m starts it, and it plays to the end, whether anyone
## stays or not. Played once: its flag (`flag`) is set at the end. A `kept` one can be heard again
## on the quest board's Logs tab (16 D); the others aren't kept anywhere.

## Who it is in the story's flags (`talk.<id>`): saved, so it never changes.
@export var id: StringName
## Where it's held: the name of a `TalkSpot` node, unique aboard and at the stations.
@export var spot: StringName
## What's said, one after another; exactly two speakers (the first line's takes the spot's first
## place).
@export var lines: Array[TalkLine] = []
## Story flags it needs before they meet (e.g. a beat's).
@export var requires: Array[StringName] = []
## Whether it's important enough to be heard again later (the quest board's Logs tab, 16 D).
@export var kept: bool = false


## Its story flag, set once it's played to the end: `talk.<id>`.
func flag() -> StringName:
	return StringName("talk.%s" % id)


## Who talks (their `NpcProfile.id`s), in the order they first speak.
func speakers() -> Array[StringName]:
	var found: Array[StringName] = []
	for line: TalkLine in lines:
		if line and line.npc not in found:
			found.append(line.npc)
	return found


## Whether it waits to be played: its flags set in `story`, played not yet.
func is_open(story: Story) -> bool:
	return story.is_set_all(requires) and not story.is_set(flag())


## Every line said in it, by who says it (see `VoiceLines.SPEAKING`).
func spoken_lines() -> Dictionary[StringName, PackedStringArray]:
	var said: Dictionary[StringName, PackedStringArray] = {}
	for line: TalkLine in lines:
		var theirs: PackedStringArray = said.get(line.npc, PackedStringArray())
		if line.text not in theirs:
			theirs.append(line.text)
		said[line.npc] = theirs
	return said
