class_name ReputationCondition
extends BeatCondition
## An NPC's reputation (`QuestLog.reputation`): at least `pips` with `npc` (their `NpcProfile.id`).

@export var npc: StringName
@export_range(0, 5) var pips: int = 1


func holds(director: StoryDirector, _beat: Beat) -> bool:
	var trust: int = director.quests.reputation.get(npc, 0)
	return trust >= pips
