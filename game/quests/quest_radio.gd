class_name QuestRadio
extends Node
## The accepted quests' calls over the radio (see docs/design/missions.md, Quests), the ship's: the
## NPC a step is handed in at calls in (`CrewReactions.call_radio`, after the crew's own calls)
## when the players land in a region where one of its goals is open (`RegionGoal.landing_line`,
## once per step), and when a goal gets done (`QuestGoal.done_line`): out in a region the moment
## what's counted and carried there makes it up (the last nest down, the last fragment picked up),
## aboard when the quest log counts it. Once all of a step's goals are done its
## `QuestStep.ready_line` comes instead. The tracked quest's calls go first. What's heard is kept
## with the quests (`QuestLog.calls`) and said again at that NPC.

## The ship whose quests call.
var ship: Ship

## The visit the players landed in (its goals done out there are called in), or null.
var _visit: QuestVisit
## Its entries whose goals are done out there, called in once each.
var _done: Array[QuestVisit.Entry] = []


func _ready() -> void:
	ship.player_left.connect(_on_player_left)
	ship.quests.goal_done.connect(_on_goal_done)


## The players landed in `visit` (the first one stepped out): its landing lines are called in
## (once per step), and its goals done out there from now on; nothing for the visit landed in
## already.
func land(visit: QuestVisit) -> void:
	if not visit or visit == _visit:
		return
	if _visit:
		_visit.counted.disconnect(_on_counted)
	_visit = visit
	_done.clear()
	visit.counted.connect(_on_counted)
	var quests: QuestLog = ship.quests
	for entry: QuestVisit.Entry in _in_order(visit.entries):
		var key: StringName = QuestStep.landing_key(entry.goal)
		var line: RadioLine = entry.step.radio_line(key)
		if line and _is_active(entry) and quests.calls.hear(entry.quest, key):
			_call(entry.quest, entry.step, line, key)


## A player stepped out: what they pick up counts out there; the first one lands in the visit.
func _on_player_left(player: Player) -> void:
	if not is_inside_tree() or not player.radio.is_inside_tree():
		return
	if not player.quest_pack.changed.is_connected(_check_visit):
		player.quest_pack.changed.connect(_check_visit)
	land(ship.get_quest_visit())


func _on_counted(_entry: QuestVisit.Entry) -> void:
	_check_visit()


## Calls in about the visit's goals done out there since the last look.
func _check_visit() -> void:
	if not _visit:
		return
	for entry: QuestVisit.Entry in _in_order(_visit.entries):
		if entry in _done or not _is_active(entry) or not _visit.is_done(entry, _carried(entry)):
			continue
		_done.append(entry)
		_goal_done(entry.quest, entry.step, entry.goal)


## A goal the quest log counted: one done aboard (out in a region it was called in already).
func _on_goal_done(quest: Quest, index: int) -> void:
	var step: QuestStep = ship.quests.current_step(quest)
	if step and not step.goals[index] is RegionGoal:
		_goal_done(quest, step, index)


## Calls in about goal `index` of `quest`'s active `step` done: its done line, or the step's ready
## line once all its goals are.
func _goal_done(quest: Quest, step: QuestStep, index: int) -> void:
	var key: StringName = QuestStep.done_key(index)
	if step.ready_line and _is_ready(quest, step):
		key = QuestStep.READY
	var line: RadioLine = step.radio_line(key)
	if not line:
		return
	ship.quests.calls.hear(quest, key)
	_call(quest, step, line, key)


## Whether every goal of `quest`'s active `step` is done: counted in the quest log, or out in the
## visit.
func _is_ready(quest: Quest, step: QuestStep) -> bool:
	for i: int in step.goals.size():
		if ship.quests.goal_progress(quest, i) >= step.goals[i].target():
			continue
		var out_there: bool = _done.any(
			func(entry: QuestVisit.Entry) -> bool: return entry.quest == quest and entry.goal == i
		)
		if not out_there:
			return false
	return true


## `line` of `quest`'s `step` (its call `key`) from the NPC it's handed in at (or the line's
## `RadioLine.speaker`), to every living player.
func _call(quest: Quest, step: QuestStep, line: RadioLine, key: StringName) -> void:
	var who: StringName = line.speaker if not line.speaker.is_empty() else quest.hand_in_npc(step)
	var caller: NpcProfile = NpcProfile.find(who)
	var english: String = line.for_players(ship.reactions.is_together())
	if not caller or english.is_empty():
		return
	ship.reactions.call_radio(caller, english, StringName("quest.%s.%s" % [quest.id, key]))
	# Heard: saved with the quests.
	ship.quests.emit_changed()


## Whether `entry`'s step is still its quest's active one (a guest aboard may have handed it in).
func _is_active(entry: QuestVisit.Entry) -> bool:
	return ship.quests.current_step(entry.quest) == entry.step


## How many of `entry`'s fragments or items the players carry.
func _carried(entry: QuestVisit.Entry) -> int:
	var count: int = 0
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		count += player.quest_pack.carried.count(entry)
	return count


## `entries` with the tracked quest's first.
func _in_order(entries: Array[QuestVisit.Entry]) -> Array[QuestVisit.Entry]:
	var tracked: Array[QuestVisit.Entry] = []
	var others: Array[QuestVisit.Entry] = []
	for entry: QuestVisit.Entry in entries:
		if entry.quest.id == ship.quests.tracked:
			tracked.append(entry)
		else:
			others.append(entry)
	tracked.append_array(others)
	return tracked
