class_name VisitQuests
extends QuestLog
## The ship's quests as an NPC waiting out in a location sees them (a meeting, see
## `QuestVisit.meetings`, e.g. Hollis at his camp): the same quests, but a goal is as far as it is
## out here (`QuestVisit.progress`: what's counted and not committed yet, and what the players
## carry of it), and a step handed in at them is handed in out here (`QuestVisit.hand_in`).
## It reads the ship's quests' state (shared again whenever they change) and writes through them:
## a quest accepted or tracked here is the ship's (`accept`, `track`), so the ship's quests emit
## `changed` and this view follows. The ship's own systems (hauls, runs, saves) only ever write to
## the ship's quests.

## The visit they wait in.
var visit: QuestVisit

## The ship's quests (weak: they're connected to this, which mustn't keep them alive).
var _ship_quests: WeakRef


func _init(ship_quests: QuestLog = null, in_visit: QuestVisit = null) -> void:
	visit = in_visit
	if not ship_quests:
		return
	_ship_quests = weakref(ship_quests)
	_share(ship_quests)
	ship_quests.changed.connect(_follow)


func goal_progress(quest: Quest, index: int) -> float:
	return visit.progress(quest, index, _players()) if visit else super(quest, index)


## Accepts `quest` in the ship's quests (see `QuestLog.accept`).
func accept(quest: Quest, players: Array[Player]) -> bool:
	var ship_quests: QuestLog = _ship()
	return ship_quests != null and ship_quests.accept(quest, players)


## Tracks `quest` in the ship's quests (see `QuestLog.track`).
func track(quest: Quest) -> bool:
	var ship_quests: QuestLog = _ship()
	return ship_quests != null and ship_quests.track(quest)


func hand_in(quest: Quest, payer: Player, players: Array[Player]) -> bool:
	return visit != null and visit.hand_in(quest, payer, players)


## The ship's quests, or null once they're gone.
func _ship() -> QuestLog:
	return _ship_quests.get_ref() as QuestLog if _ship_quests else null


## Reads `ship_quests`' state: the same objects, and the quest tracked (a plain value).
func _share(ship_quests: QuestLog) -> void:
	catalog = ship_quests.catalog
	story = ship_quests.story
	furnaces = ship_quests.furnaces
	cradles = ship_quests.cradles
	accepted = ship_quests.accepted
	progress = ship_quests.progress
	last_requests = ship_quests.last_requests
	tracked = ship_quests.tracked
	calls = ship_quests.calls


## The players in the session (what they carry counts out here).
func _players() -> Array[Player]:
	var found: Array[Player] = []
	var tree := Engine.get_main_loop() as SceneTree
	for node: Node in tree.get_nodes_in_group(Player.GROUP) if tree else []:
		var player := node as Player
		if player and not player.dead:
			found.append(player)
	return found


## The ship's quests changed: so do these.
func _follow() -> void:
	var ship_quests: QuestLog = _ship()
	if ship_quests:
		_share(ship_quests)
	emit_changed()
