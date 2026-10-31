class_name TourStop
extends Resource
## A stop of a `Tour`: where to stand (`id`, the name of a marker under the ship's `Tour`: their
## feet, facing the way it faces) and what to say there, one speech bubble each. A stop at a crew
## member's room who joins later (`crew_member`) says `empty_lines` until they're aboard.

@export var id: StringName
## What they say there (the English texts, translated), one speech bubble each.
@export var lines: Array[String] = []
## Whose room it is: their `NpcProfile.id`, when its `lines` name them; empty: nobody's.
@export var crew_member: StringName = &""
## What they say there instead while `crew_member` isn't aboard yet (the English texts,
## translated), without naming them.
@export var empty_lines: Array[String] = []


## What they say there with `story` as it is: `empty_lines` while `crew_member` isn't aboard.
func lines_for(story: Story) -> Array[String]:
	if crew_member.is_empty():
		return lines
	var member: NpcProfile = NpcProfile.find(crew_member)
	return lines if not member or member.is_aboard(story) else empty_lines
