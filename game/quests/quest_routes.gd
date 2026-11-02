class_name QuestRoutes
extends RefCounted
## Where the active quest steps of a `QuestLog` lead the ship: the regions with something to do
## (`regions`, the navigator's diamonds) and where to go for one quest (`destination`, the quest
## board's "Set as destination").


## The regions (their `Region.id`) where a goal of an active step of `quest_log` isn't done yet, or
## where a step meets someone: whether one of them is the tracked quest's (the navigator's
## diamonds).
static func regions(quest_log: QuestLog) -> Dictionary[StringName, bool]:
	var found: Dictionary[StringName, bool] = {}
	for id: StringName in quest_log.accepted:
		var quest: Quest = quest_log.catalog.find(id)
		var step: QuestStep = quest_log.current_step(quest) if quest else null
		if not step:
			continue
		var tracked: bool = id == quest_log.tracked
		if step.meets_out_there():
			found[step.meets_in] = found.get(step.meets_in, false) or tracked
		for goal: RegionGoal in _open_goals(quest_log, quest, step):
			found[goal.region] = found.get(goal.region, false) or tracked
	return found


## Where the ship goes for `quest`'s active step: the region (its `Region.id`) of its first goal
## out there not done yet, else the region where it meets someone, else the station (its
## `CelestialBody.id`) of whoever it's handed in at; empty when it's all done aboard (or no step
## is active).
static func destination(quest_log: QuestLog, quest: Quest) -> StringName:
	var step: QuestStep = quest_log.current_step(quest) if quest else null
	if not step:
		return &""
	var open: Array[RegionGoal] = _open_goals(quest_log, quest, step)
	if not open.is_empty():
		return open[0].region
	if step.meets_out_there():
		return step.meets_in
	var profile: NpcProfile = NpcProfile.find(quest.hand_in_npc(step))
	return profile.station_in(quest_log.story) if profile else &""


## The goals out in a region of `quest`'s active `step` that aren't done yet, in order.
static func _open_goals(quest_log: QuestLog, quest: Quest, step: QuestStep) -> Array[RegionGoal]:
	var open: Array[RegionGoal] = []
	for i: int in step.goals.size():
		var goal := step.goals[i] as RegionGoal
		if goal and quest_log.goal_progress(quest, i) < goal.target():
			open.append(goal)
	return open
