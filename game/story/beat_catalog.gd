class_name BeatCatalog
extends Resource
## Every beat in the game (`game/story/beats.tres`), in the order they go on a tie of priority.

@export var beats: Array[Beat] = []


## The beat with `id`, or null.
func find(id: StringName) -> Beat:
	for beat: Beat in beats:
		if beat.id == id:
			return beat
	return null
