class_name QuestVisit
extends RefCounted
## What the active quest steps put into one visit to a region (see docs/planned/quests.md, Quest
## sites), made when its location is prepared: a quest site per goal that has one, the quest nests
## still to destroy. What's done there is counted here (`count`) and goes into the ship's quests
## once someone is back aboard (`commit`); a lost run drops it (`drop`).


## One goal of an active step done in the region.
class Entry:
	var quest: Quest
	var step: QuestStep
	## Its index among the step's goals.
	var goal: int
	## The map part of its quest site (a copy of the goal's, so every site is a part of its own),
	## or null.
	var site: PartPlacement
	## How many quest nests it puts into the visit.
	var nests: int
	## What's done this visit and not counted yet, and what's left of the goal when the visit was
	## made.
	var pending: float = 0.0
	var room: float = 0.0


var entries: Array[Entry] = []

var _log: QuestLog


## The visit to `region` (a `Region.id`): every goal there of the active steps of `quest_log` that
## isn't done.
func _init(quest_log: QuestLog = null, region: StringName = &"") -> void:
	_log = quest_log
	if not quest_log or region.is_empty():
		return
	for id: StringName in quest_log.accepted:
		var quest: Quest = quest_log.catalog.find(id)
		var step: QuestStep = quest_log.current_step(quest) if quest else null
		if not step:
			continue
		for i: int in step.goals.size():
			var goal := step.goals[i] as RegionGoal
			var so_far: float = quest_log.goal_progress(quest, i)
			if not goal or goal.region != region or so_far >= goal.target():
				continue
			var entry := Entry.new()
			entry.quest = quest
			entry.step = step
			entry.goal = i
			entry.site = goal.site().duplicate() if goal.site() else null
			entry.nests = goal.nests(so_far)
			entry.room = goal.target() - so_far
			entries.append(entry)


## The quest sites' map parts, to place as set pieces.
func sites() -> Array[PartPlacement]:
	var parts: Array[PartPlacement] = []
	for entry: Entry in entries:
		if entry.site:
			parts.append(entry.site)
	return parts


## For every quest nest, the entry it belongs to.
func nest_entries() -> Array[Entry]:
	var nests: Array[Entry] = []
	for entry: Entry in entries:
		for i: int in entry.nests:
			nests.append(entry)
	return nests


## Counts `amount` done towards `entry`'s goal this visit (up to what was left of it).
func count(entry: Entry, amount: float = 1.0) -> void:
	entry.pending = minf(entry.pending + amount, entry.room)


## Puts what's counted into the ship's quests (someone is back aboard).
func commit() -> void:
	for entry: Entry in entries:
		if entry.pending <= 0.0:
			continue
		if _log:
			_log.add_progress(entry.quest, entry.step, entry.goal, entry.pending)
		entry.room -= entry.pending
		entry.pending = 0.0


## Forgets what's counted and not committed (a lost run).
func drop() -> void:
	for entry: Entry in entries:
		entry.pending = 0.0


## What it puts into the location, as text: two visits with the same key place the same things.
func key() -> String:
	var parts: PackedStringArray = []
	for entry: Entry in entries:
		var site: String = entry.site.scene.resource_path if entry.site else ""
		parts.append(
			"%s/%s/%d/%s/%d" % [entry.quest.id, entry.step.id, entry.goal, site, entry.nests]
		)
	return ";".join(parts)
