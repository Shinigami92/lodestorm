class_name StationWait
extends RefCounted
## Someone at a station waiting for the players (see docs/design/story.md, Between missions): a beat
## they carry, put out and waiting, or a quest step handed in at them with all its goals done. The
## navigator shows an amber diamond on their station, and they call the ship once (`MessageLog`).

## What waits, as its story flag (the beat's, or the step's once handed in): it keeps the call to
## one.
var key: StringName
## Who waits: their `NpcProfile.id`.
var npc: StringName
## Where: their station's `CelestialBody.id`.
var station: StringName
## The quest whose step waits; null: a beat.
var quest: Quest


func _init(what: StringName, who: StringName, where: StringName, of_quest: Quest = null) -> void:
	key = what
	npc = who
	station = where
	quest = of_quest


## Everything waiting at a station now: `director`'s waiting beats carried by someone who lives on
## one, then the quests' (`director.quests`) active steps handed in at someone there with every
## goal done, in the order accepted.
static func find_all(director: StoryDirector) -> Array[StationWait]:
	var found: Array[StationWait] = []
	for beat: Beat in director.waiting():
		var where: StringName = _station_of(beat.npc)
		if not where.is_empty():
			found.append(StationWait.new(beat.flag(), beat.npc, where))
	var quests: QuestLog = director.quests
	for id: StringName in quests.accepted:
		var accepted: Quest = quests.catalog.find(id)
		var step: QuestStep = quests.current_step(accepted) if accepted else null
		if not step or not _goals_done(quests, accepted, step):
			continue
		var at_npc: StringName = accepted.hand_in_npc(step)
		var where: StringName = _station_of(at_npc)
		if not where.is_empty():
			found.append(StationWait.new(accepted.step_flag(step), at_npc, where, accepted))
	return found


## The station `who` (an `NpcProfile.id`) lives on, or empty (aboard, or nobody).
static func _station_of(who: StringName) -> StringName:
	var profile: NpcProfile = NpcProfile.find(who) if not who.is_empty() else null
	return profile.station if profile else &""


## Whether every goal of `step` (the active one of `of_quest`) is done, deliveries filled.
static func _goals_done(quests: QuestLog, of_quest: Quest, step: QuestStep) -> bool:
	for i: int in step.goals.size():
		if quests.goal_progress(of_quest, i) < step.goals[i].target():
			return false
	return true
