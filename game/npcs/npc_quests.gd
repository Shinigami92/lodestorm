class_name NpcQuests
extends RefCounted
## A crew member's (`npc`) quests (see docs/design/quests.md): the quest log their topics heard and
## steps handed in go into (`get_log`: the ship's, or as seen where they stand, `Npc.quests_view`),
## the entries at the top of their talk list (`get_choices`: the steps handed in at them and the
## quests they offer) and whether the diamond above their head shows (`has_news`).

## Whose quests they are.
var npc: Npc

## Used without a ship (e.g. tests of a lone NPC).
var _own := QuestLog.new()


## `own_story`: the story of `who` without a ship.
func _init(who: Npc, own_story: Story) -> void:
	npc = who
	_own.story = own_story


## The quests the topics heard and handed in go into: the ship's (as seen from where they stand,
## `Npc.quests_view`).
func get_log() -> QuestLog:
	if npc.quests_view:
		return npc.quests_view
	return npc.ship.quests if npc.ship else _own


## The quest entries at the top of their list for `listener` (the player talking to them when
## null; the talk card sets them apart): the steps handed in at them that `listener` can hand in
## now, then the quests they offer, then the other steps handed in at them.
func get_choices(listener: Player = null) -> Array[Topic]:
	var entries: Array[Topic] = []
	if not npc.profile or _on_tour():
		return entries
	if not listener:
		listener = npc.user
	var quests: QuestLog = get_log()
	var steps: Array[Quest] = quests.steps_at(npc.profile.id)
	var can_hand: Array[Quest] = steps.filter(
		func(quest: Quest) -> bool:
			return listener != null and quests.can_hand_in(quest, listener.hold)
	)
	for quest: Quest in can_hand:
		entries.append(quests.current_step(quest).hand_in)
	for quest: Quest in _offered(quests):
		entries.append(quest.offer)
	for quest: Quest in steps:
		if quest not in can_hand:
			entries.append(quests.current_step(quest).hand_in)
	return entries


## Whether they offer `listener` (the player talking to them when null) a quest, or `listener` can
## hand in a quest step at them now (the diamond marker); not at their place before joining
## without anything to say there (`NpcPresence.talks_here`), nor during their tour.
func has_news(listener: Player = null) -> bool:
	if not npc.profile or not npc.presence.talks_here() or _on_tour():
		return false
	var quests: QuestLog = get_log()
	if not _offered(quests).is_empty():
		return true
	var payer: Player = listener if listener else npc.user
	return (
		payer != null
		and quests.steps_at(npc.profile.id).any(
			func(quest: Quest) -> bool: return quests.can_hand_in(quest, payer.hold)
		)
	)


## The ids of the topics the offers of their quests took the place of (`Quest.replaces`): of the
## quests they give whose `requires` are set.
func replaced_topics() -> Array[StringName]:
	var replaced: Array[StringName] = []
	var story: Story = npc.get_story()
	for quest: Quest in get_log().catalog.quests:
		if quest.giver == npc.profile.id and not quest.replaces.is_empty():
			if story.is_set_all(quest.requires):
				replaced.append(quest.replaces)
	return replaced


## The ids of the planets and moons the ship reaches now (for topics and quests about them, see
## `Topic.requires_body`, `Quest.requires_body`): none without a ship on a voyage.
func reached_bodies() -> Array[StringName]:
	var ship: Ship = npc.ship
	var voyage: Voyage = ship.voyage if ship else null
	var system: StarSystem = voyage.settings.system if voyage and voyage.settings else null
	return system.reached_bodies(ship.heat_shield.mk) if system else [] as Array[StringName]


## The quests they offer now.
func _offered(quests: QuestLog) -> Array[Quest]:
	return quests.offered_by(npc.profile.id, reached_bodies(), npc.profile.open_requests)


func _on_tour() -> bool:
	return npc.routine != null and npc.routine.tour != null
