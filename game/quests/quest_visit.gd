class_name QuestVisit
extends RefCounted
## What the active quest steps put into one visit to a region (see docs/planned/quests.md, Quest
## sites), made when its location is prepared: a quest site per goal that has one, the quest nests
## still to destroy, a hunt's brood nest or lair at its site, the fragments still to find in the
## crates, an item at its site. What's done there is counted here (`count`, a hunt's `count_kill`
## and `count_brood`, carried items brought aboard with `count_carried`) and goes into the ship's
## quests once someone is back aboard (`commit`); a lost run drops it (`drop`). A brood nest
## destroyed counts once the hunt's kills are all done (in this visit or before), so it stays
## waiting until they are.


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
	## The strain it hunts at its site, and the brood nest hatching it there (null: it sleeps in
	## a lair there).
	var hunted: AlienStrain
	var brood: PackedScene
	## How many fragments it puts into the crates, and the look of the item at its site (or null).
	var fragments: int
	var item: PackedScene
	## Whether its brood nest was destroyed this visit and isn't counted yet.
	var brood_down: bool = false
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
			entry.hunted = goal.hunted()
			entry.brood = goal.brood_nest()
			entry.fragments = goal.fragments(so_far)
			entry.item = goal.item_look()
			entry.room = goal.target() - so_far
			entries.append(entry)


## The regions (their `Region.id`) where a goal of an active step of `quest_log` isn't done yet:
## whether one of them is the tracked quest's (the navigator's diamonds).
static func regions(quest_log: QuestLog) -> Dictionary[StringName, bool]:
	var found: Dictionary[StringName, bool] = {}
	for id: StringName in quest_log.accepted:
		var quest: Quest = quest_log.catalog.find(id)
		var step: QuestStep = quest_log.current_step(quest) if quest else null
		if not step:
			continue
		for i: int in step.goals.size():
			var goal := step.goals[i] as RegionGoal
			if goal and quest_log.goal_progress(quest, i) < goal.target():
				found[goal.region] = found.get(goal.region, false) or id == quest_log.tracked
	return found


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


## For every fragment to put into a crate, the entry it belongs to.
func fragment_entries() -> Array[Entry]:
	var fragments: Array[Entry] = []
	for entry: Entry in entries:
		for i: int in entry.fragments:
			fragments.append(entry)
	return fragments


## Whether `entry`'s quest is the one tracked (its marks show, see `QuestMark`).
func is_tracked(entry: Entry) -> bool:
	return _log != null and _log.tracked == entry.quest.id


## Counts `amount` done towards `entry`'s goal this visit (up to what was left of it).
func count(entry: Entry, amount: float = 1.0) -> void:
	entry.pending = minf(entry.pending + amount, entry.room)


## Counts what a player brought aboard (`QuestPack.take_all`): a fragment or an item each.
func count_carried(carried: Array[Entry]) -> void:
	for entry: Entry in carried:
		if entry in entries:
			count(entry)


## Counts a kill for `entry`'s hunt (with a brood nest, up to the kills left: the nest is the last).
func count_kill(entry: Entry) -> void:
	entry.pending = minf(entry.pending + 1.0, entry.room - (1.0 if entry.brood else 0.0))


## `entry`'s brood nest was destroyed: it counts once the kills are all done.
func count_brood(entry: Entry) -> void:
	entry.brood_down = true


## How many kills `entry`'s brood nest may still hatch: what's left of its hunt but the nest.
func kills_left(entry: Entry) -> int:
	return maxi(floori(entry.room - entry.pending) - 1, 0)


## Whether a hunt here has the hive's `apex` sleep in its lair (the location's own roams no more).
func has_lair(apex: AlienStrain) -> bool:
	for entry: Entry in entries:
		if entry.hunted == apex and not entry.brood:
			return true
	return false


## Puts what's counted into the ship's quests (someone is back aboard).
func commit() -> void:
	for entry: Entry in entries:
		if entry.brood_down and entry.pending >= entry.room - 1.0:
			entry.pending += 1.0
			entry.brood_down = false
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
		entry.brood_down = false


## What it puts into the location, as text: two visits with the same key place the same things.
func key() -> String:
	var parts: PackedStringArray = []
	for entry: Entry in entries:
		var site: String = entry.site.scene.resource_path if entry.site else ""
		var brood: String = entry.brood.resource_path if entry.brood else ""
		var item: String = entry.item.resource_path if entry.item else ""
		var room: float = entry.room if entry.hunted else 0.0
		(
			parts
			. append(
				(
					"%s/%s/%d/%s/%d/%s/%s/%d/%s"
					% [
						entry.quest.id,
						entry.step.id,
						entry.goal,
						site,
						entry.nests,
						brood,
						room,
						entry.fragments,
						item,
					]
				)
			)
		)
	return ";".join(parts)
