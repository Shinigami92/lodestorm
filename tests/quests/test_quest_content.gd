extends GutTest
## The game's quests (`game/quests/quests.tres`): ids that save, NPCs that exist, topics named
## after who says them, and steps that can be done (in regions that exist).

const NPC_FOLDERS: Array[String] = ["res://game/npcs/crew/", "res://game/npcs/ostra/"]
const SYSTEM: StarSystem = preload("res://game/world/star_system.tres")


func test_every_quest_keeps_to_the_scheme() -> void:
	var npcs: Array[StringName] = _npc_ids()
	assert_gt(npcs.size(), 0)
	var ids: Array[StringName] = []
	for quest: Quest in QuestLog.CATALOG.quests:
		var what: String = String(quest.id)
		assert_true(Story.is_valid_flag(quest.flag()), "%s: its id" % what)
		assert_does_not_have(ids, quest.id, "%s: once" % what)
		ids.append(quest.id)
		assert_false(quest.title.is_empty(), "%s: a title" % what)
		assert_has(npcs, quest.giver, "%s: its giver" % what)
		assert_not_null(quest.offer, "%s: an offer" % what)
		if quest.offer:
			_assert_said_by(quest.offer, quest.giver, what)
		assert_false(quest.steps.is_empty(), "%s: steps" % what)
		var steps: Array[StringName] = []
		for step: QuestStep in quest.steps:
			var where: String = "%s.%s" % [what, step.id]
			assert_true(Story.is_valid_flag(quest.step_flag(step)), "%s: its id" % where)
			assert_does_not_have(steps, step.id, "%s: once" % where)
			steps.append(step.id)
			assert_false(step.text.is_empty(), "%s: what it asks" % where)
			assert_false(step.goals.is_empty(), "%s: goals" % where)
			for goal: QuestGoal in step.goals:
				_assert_doable(goal, where)
			assert_has(npcs, quest.hand_in_npc(step), "%s: who it's handed in at" % where)
			assert_not_null(step.hand_in, "%s: a hand-in" % where)
			if step.hand_in:
				_assert_said_by(step.hand_in, quest.hand_in_npc(step), where)


## `goal` is done in a region that exists, a site's goal has its site and says what it is.
func _assert_doable(goal: QuestGoal, where: String) -> void:
	var out_there := goal as RegionGoal
	if out_there:
		assert_not_null(SYSTEM.region_by_id(out_there.region), "%s: its region" % where)
	var reach := goal as ReachGoal
	if reach:
		assert_not_null(reach.site_part, "%s: its site" % where)
		assert_false(reach.place.is_empty(), "%s: what its site is" % where)


## `topic` has a title, lines and an id of `npc`'s.
func _assert_said_by(topic: Topic, npc: StringName, what: String) -> void:
	assert_false(topic.title.is_empty(), "%s: %s has a title" % [what, topic.id])
	assert_false(topic.lines.is_empty(), "%s: %s has lines" % [what, topic.id])
	assert_true(String(topic.id).begins_with("%s." % npc), "%s: %s is %s's" % [what, topic.id, npc])


## The ids of every named NPC.
func _npc_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for folder: String in NPC_FOLDERS:
		for file: String in DirAccess.get_files_at(folder):
			if file.get_extension() == "tres":
				ids.append((load(folder.path_join(file)) as NpcProfile).id)
	return ids
