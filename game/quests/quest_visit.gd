class_name QuestVisit
extends RefCounted
## What the active quest steps put into one visit to a region (see docs/planned/quests.md, Quest
## sites), made when its location is prepared: a quest site per goal that has one, the quest nests
## still to destroy, a hunt's brood nest or lair at its site, the fragments still to find in the
## crates, an item at its site, and the NPCs waiting there for a step to be handed in (`meetings`).
## What's done there is counted here (`count`, a hunt's `count_kill` and `count_brood`, carried
## items brought aboard with `count_carried`) and goes into the ship's quests once someone is back
## aboard (`commit`); a lost run drops it (`drop`). A brood nest destroyed counts once the hunt's
## kills are all done (in this visit or before), so it stays waiting until they are.
## A step handed in at someone out here (see `QuestStep.meets_at`, e.g. Hollis at his camp) is
## handed in during the run (`hand_in`): what's done here for it counts at once, the quest log hands
## it in and the next step's goals here join the visit (`extended`). Until someone is back aboard
## (`commit`), a lost run takes it back (`drop`): its progress, its flags and its calls heard are as
## before (a step met out here pays nothing but a crew member joining, so there's nothing else to
## take back). The next step's goals in the region are there already (`Entry.upcoming`, e.g. the
## nest around Hollis' miner before he tells about it, and the crate with his part): what's done of
## them counts once that step starts.

## Emitted when something is counted towards `entry`'s goal this visit (see `is_done`).
signal counted(entry: Entry)
## Emitted when a step handed in out here started the next one: its goals here (`added`, now among
## `entries`) and, if it meets someone here too, its meeting (else null).
signal extended(added: Array[Entry], meeting: Entry)


## One goal of an active step done in the region, or an NPC waiting there (a meeting).
class Entry:
	var quest: Quest
	var step: QuestStep
	## Its index among the step's goals; -1 for a meeting (see `meetings`).
	var goal: int
	## The map part of its quest site (a copy of the goal's: every site is a part of its own, but
	## goals and meetings at the same part share it), or null.
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
	## Whether it's the next step's (after a step met here, there already); it counts once that step
	## starts.
	var upcoming: bool = false


## What a step handed in out here changed in the quest log (see `hand_in`), to take back.
class HandedIn:
	var quest: Quest
	## The quest's progress, the quest tracked and its calls heard before it.
	var progress: PackedFloat64Array
	var tracked: StringName
	var heard: PackedStringArray
	## The story flags it set.
	var flags: Array[StringName] = []


var entries: Array[Entry] = []
## The NPCs waiting out here for a step to be handed in, one per active step that
## `QuestStep.meets_at` the region: its quest and step, the map part they stand at (`site`) and
## `goal` -1.
var meetings: Array[Entry] = []

var _log: QuestLog
var _region: StringName
## Per goal's or step's part, its copy in this visit (see `Entry.site`).
var _sites: Dictionary[PartPlacement, PartPlacement] = {}
## The steps handed in out here and not counted yet (see `commit`), in the order they were.
var _handed: Array[HandedIn] = []


## The visit to `region` (a `Region.id`): every goal there of the active steps of `quest_log` that
## isn't done, and every step meeting someone there.
func _init(quest_log: QuestLog = null, region: StringName = &"") -> void:
	_log = quest_log
	_region = region
	if not quest_log or region.is_empty():
		return
	for id: StringName in quest_log.accepted:
		var quest: Quest = quest_log.catalog.find(id)
		var step: QuestStep = quest_log.current_step(quest) if quest else null
		if step:
			_add_step(quest, step)


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
		if not step.meets_in.is_empty() and step.meets_at:
			found[step.meets_in] = found.get(step.meets_in, false) or tracked
		for i: int in step.goals.size():
			var goal := step.goals[i] as RegionGoal
			if goal and quest_log.goal_progress(quest, i) < goal.target():
				found[goal.region] = found.get(goal.region, false) or tracked
	return found


## Where the ship goes for `quest`'s active step (the quest board's "Set as destination"): the
## region (its `Region.id`) of its first goal out there not done yet, else the region where it meets
## someone, else the station (its `CelestialBody.id`) of whoever it's handed in at; empty when it's
## all done aboard (or no step is active).
static func destination(quest_log: QuestLog, quest: Quest) -> StringName:
	var step: QuestStep = quest_log.current_step(quest) if quest else null
	if not step:
		return &""
	for i: int in step.goals.size():
		var goal := step.goals[i] as RegionGoal
		if goal and quest_log.goal_progress(quest, i) < goal.target():
			return goal.region
	if not step.meets_in.is_empty() and step.meets_at:
		return step.meets_in
	var profile: NpcProfile = NpcProfile.find(quest.hand_in_npc(step))
	return profile.station if profile else &""


## The quest sites' map parts, to place as set pieces (each once, also when goals and meetings
## share it).
func sites() -> Array[PartPlacement]:
	var parts: Array[PartPlacement] = []
	for entry: Entry in meetings + entries:
		if entry.site and entry.site not in parts:
			parts.append(entry.site)
	return parts


## For every quest nest spread over the region, the entry it belongs to (those of a goal with a
## site grow at its part, see `ClearNestsGoal.site_part`).
func nest_entries() -> Array[Entry]:
	var nests: Array[Entry] = []
	for entry: Entry in entries:
		if entry.site:
			continue
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


## Whether `entry`'s quest is the one tracked and its step has started (its marks show, see
## `QuestMark`).
func is_tracked(entry: Entry) -> bool:
	return _log != null and _log.tracked == entry.quest.id and not entry.upcoming


## Counts `amount` done towards `entry`'s goal this visit (up to what was left of it).
func count(entry: Entry, amount: float = 1.0) -> void:
	entry.pending = minf(entry.pending + amount, entry.room)
	counted.emit(entry)


## Counts what a player brought aboard (`QuestPack.take_all`): a fragment or an item each.
func count_carried(carried: Array[Entry]) -> void:
	for entry: Entry in carried:
		if entry in entries:
			count(entry)


## Counts a kill for `entry`'s hunt (with a brood nest, up to the kills left: the nest is the last).
func count_kill(entry: Entry) -> void:
	entry.pending = minf(entry.pending + 1.0, entry.room - (1.0 if entry.brood else 0.0))
	counted.emit(entry)


## `entry`'s brood nest was destroyed: it counts once the kills are all done.
func count_brood(entry: Entry) -> void:
	entry.brood_down = true
	counted.emit(entry)


## Whether `entry`'s goal is done out here, with `carried` of its fragments or items picked up and
## still carried: what's counted (its brood nest once the kills are all done) and carried makes up
## what was left of it. It still counts only once someone is back aboard.
func is_done(entry: Entry, carried: int = 0) -> bool:
	return _done_here(entry, carried) >= entry.room


## How many kills `entry`'s brood nest may still hatch: what's left of its hunt but the nest.
func kills_left(entry: Entry) -> int:
	return maxi(floori(entry.room - entry.pending) - 1, 0)


## Whether a hunt here has the hive's `apex` sleep in its lair (the location's own roams no more).
func has_lair(apex: AlienStrain) -> bool:
	for entry: Entry in entries:
		if entry.hunted == apex and not entry.brood:
			return true
	return false


## How far goal `index` of `quest`'s active step is out here: the quest log's, what's counted here
## and not committed yet, and the fragments or items of it that `carriers` carry (up to the goal's
## target).
func progress(quest: Quest, index: int, carriers: Array[Player] = []) -> float:
	var step: QuestStep = _log.current_step(quest) if _log else null
	if not step or index < 0 or index >= step.goals.size():
		return 0.0
	var so_far: float = _log.goal_progress(quest, index)
	for entry: Entry in entries:
		if entry.quest != quest or entry.step != step or entry.goal != index:
			continue
		var carried: int = 0
		for carrier: Player in carriers:
			carried += carrier.quest_pack.carried.count(entry)
		so_far += _done_here(entry, carried)
	return minf(so_far, step.goals[index].target())


## Whether `quest`'s active step's goals are all done out here, with what `carriers` carry of it.
func is_ready(quest: Quest, carriers: Array[Player] = []) -> bool:
	var step: QuestStep = _log.current_step(quest) if _log else null
	if not step:
		return false
	for i: int in step.goals.size():
		if progress(quest, i, carriers) < step.goals[i].target():
			return false
	return true


## The quests as an NPC waiting out here sees them (see `VisitQuests`).
func view() -> VisitQuests:
	return VisitQuests.new(_log, self)


## The NPC waiting out here for `quest`'s active step (its meeting), or null.
func meeting_for(quest: Quest) -> Entry:
	var step: QuestStep = _log.current_step(quest) if _log else null
	for meeting: Entry in meetings:
		if meeting.quest == quest and meeting.step == step:
			return meeting
	return null


## Hands in `quest`'s active step at its NPC out here (`meeting_for`), `payer` paying, everyone of
## `players` there, once its goals are done out here (`progress`): what's done here for it counts
## at once (the fragments and items they carry of it too), then the quest log hands it in, and the
## next step's goals here join the visit (`extended`). It can be taken back until someone is back
## aboard (see `drop`). Returns whether it did.
func hand_in(quest: Quest, payer: Player, players: Array[Player]) -> bool:
	var step: QuestStep = _log.current_step(quest) if _log else null
	if not step or not meeting_for(quest) or not is_ready(quest, players):
		return false
	var record := HandedIn.new()
	record.quest = quest
	var progress_before: PackedFloat64Array = _log.progress.get(quest.id, PackedFloat64Array())
	var heard_before: PackedStringArray = _log.calls.heard.get(quest.id, PackedStringArray())
	record.progress = progress_before.duplicate()
	record.tracked = _log.tracked
	record.heard = heard_before.duplicate()
	var flags: Array[StringName] = [quest.step_flag(step), quest.flag()]
	var joining: NpcProfile = NpcProfile.find(step.joins) if not step.joins.is_empty() else null
	if joining and not joining.join_flag.is_empty():
		flags.append(joining.join_flag)
	flags = flags.filter(func(flag: StringName) -> bool: return not _log.story.is_set(flag))
	for player: Player in players:
		_hand_over_carried(player, quest, step)
	_commit_where(func(entry: Entry) -> bool: return entry.quest == quest)
	if not _log.hand_in(quest, payer, players):
		return false
	record.flags = flags.filter(func(flag: StringName) -> bool: return _log.story.is_set(flag))
	_handed.append(record)
	var next: QuestStep = _log.current_step(quest)
	if next:
		var meeting_count: int = meetings.size()
		var added: Array[Entry] = _add_step(quest, next)
		extended.emit(added, meetings.back() if meetings.size() > meeting_count else null)
	return true


## Puts what's counted into the ship's quests (someone is back aboard); the steps handed in out
## here stay handed in.
func commit() -> void:
	_commit_where(func(_entry: Entry) -> bool: return true)
	_handed.clear()


## Forgets what's counted and not committed (a lost run), and takes back the steps handed in out
## here since someone was last aboard.
func drop() -> void:
	for entry: Entry in entries:
		entry.pending = 0.0
		entry.brood_down = false
	if not _log or _handed.is_empty():
		return
	_handed.reverse()
	for record: HandedIn in _handed:
		for flag: StringName in record.flags:
			_log.story.clear_flag(flag)
		_log.progress[record.quest.id] = record.progress
		_log.calls.heard[record.quest.id] = record.heard
		_log.tracked = record.tracked
	_handed.clear()
	_log.emit_changed()


## What it puts into the location, as text: two visits with the same key place the same things.
func key() -> String:
	var parts: PackedStringArray = []
	for meeting: Entry in meetings:
		parts.append(
			"%s/%s/%s" % [meeting.quest.id, meeting.step.id, meeting.site.scene.resource_path]
		)
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


## Adds what `quest`'s `step` (its active one) needs here: its meeting (if it meets someone in the
## region) and every goal of it in the region that isn't done; with a meeting, also the next step's
## goals in the region (upcoming). Returns the goals' entries new to the visit (those there already
## as upcoming have started now).
func _add_step(quest: Quest, step: QuestStep) -> Array[Entry]:
	var added: Array[Entry] = []
	for i: int in step.goals.size():
		var known: Array[Entry] = entries.filter(
			func(entry: Entry) -> bool: return entry.step == step and entry.goal == i
		)
		if not known.is_empty():
			known[0].upcoming = false
		else:
			added.append_array(_add_goal(quest, step, i, _log.goal_progress(quest, i)))
	if step.meets_in != _region or not step.meets_at:
		return added
	var meeting := Entry.new()
	meeting.quest = quest
	meeting.step = step
	meeting.goal = -1
	meeting.site = _site_for(step.meets_at)
	meetings.append(meeting)
	var at: int = quest.steps.find(step)
	var next: QuestStep = quest.steps[at + 1] if at + 1 < quest.steps.size() else null
	for i: int in next.goals.size() if next else 0:
		for entry: Entry in _add_goal(quest, next, i, 0.0):
			entry.upcoming = true
	return added


## Adds goal `index` of `quest`'s `step` with `so_far` done, if it's done in the region and isn't
## done yet. Returns its entry (none: nothing added).
func _add_goal(quest: Quest, step: QuestStep, index: int, so_far: float) -> Array[Entry]:
	var goal := step.goals[index] as RegionGoal
	if not goal or goal.region != _region or so_far >= goal.target():
		return []
	var entry := Entry.new()
	entry.quest = quest
	entry.step = step
	entry.goal = index
	entry.site = _site_for(goal.site())
	entry.nests = goal.nests(so_far)
	entry.hunted = goal.hunted()
	entry.brood = goal.brood_nest()
	entry.fragments = goal.fragments(so_far)
	entry.item = goal.item_look()
	entry.room = goal.target() - so_far
	entries.append(entry)
	return [entry]


## This visit's copy of `part` (one per part, shared), or null without one.
func _site_for(part: PartPlacement) -> PartPlacement:
	if not part:
		return null
	if not _sites.has(part):
		_sites[part] = part.duplicate()
	return _sites[part]


## What's done of `entry` out here, with `carried` of its fragments or items still carried: what's
## counted and carried, and its brood nest once the kills are all done.
func _done_here(entry: Entry, carried: int) -> float:
	var done: float = entry.pending + carried
	if entry.brood_down and done >= entry.room - 1.0:
		done += 1.0
	return done


## Counts what `player` carries of `quest`'s `step` (they hand it over out here) and keeps the rest
## in their pack.
func _hand_over_carried(player: Player, quest: Quest, step: QuestStep) -> void:
	var kept: Array[Entry] = []
	for entry: Entry in player.quest_pack.take_all():
		if entry.quest == quest and entry.step == step and entry in entries:
			count(entry)
		else:
			kept.append(entry)
	for entry: Entry in kept:
		player.quest_pack.add(entry)


## Puts what's counted of the entries `which` picks into the ship's quests (an upcoming one's waits
## until its step has started).
func _commit_where(which: Callable) -> void:
	for entry: Entry in entries:
		if not which.call(entry) or (_log and _log.current_step(entry.quest) != entry.step):
			continue
		if entry.brood_down and entry.pending >= entry.room - 1.0:
			entry.pending += 1.0
			entry.brood_down = false
		if entry.pending <= 0.0:
			continue
		if _log:
			_log.add_progress(entry.quest, entry.step, entry.goal, entry.pending)
		entry.room -= entry.pending
		entry.pending = 0.0
