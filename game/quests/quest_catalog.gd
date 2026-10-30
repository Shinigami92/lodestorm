class_name QuestCatalog
extends Resource
## Every quest in the game (`game/quests/quests.tres`), in the order they're listed where several
## are offered at once.

@export var quests: Array[Quest] = []


## The quest with `id`, or null.
func find(id: StringName) -> Quest:
	for quest: Quest in quests:
		if quest.id == id:
			return quest
	return null
