class_name TalkCatalog
extends Resource
## Every overheard talk in the game (`game/talks/talks.tres`), in the order they're picked when
## several wait.

@export var talks: Array[OverheardTalk] = []


## The talk with `id`, or null.
func find(id: StringName) -> OverheardTalk:
	for talk: OverheardTalk in talks:
		if talk.id == id:
			return talk
	return null
