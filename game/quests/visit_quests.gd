class_name VisitQuests
extends QuestLog
## The ship's quests as an NPC waiting out in a location sees them (a meeting, see
## `QuestVisit.meetings`, e.g. Hollis at his camp): the same quests (it shares their state), but a
## goal is as far as it is out here (`QuestVisit.progress`: what's counted and not committed yet,
## and what the players carry of it), and a step handed in at them is handed in out here
## (`QuestVisit.hand_in`).

## The visit they wait in.
var visit: QuestVisit


func _init(ship_quests: QuestLog = null, in_visit: QuestVisit = null) -> void:
	visit = in_visit
	if not ship_quests:
		return
	catalog = ship_quests.catalog
	story = ship_quests.story
	furnaces = ship_quests.furnaces
	cradles = ship_quests.cradles
	accepted = ship_quests.accepted
	progress = ship_quests.progress
	last_requests = ship_quests.last_requests
	tracked = ship_quests.tracked
	calls = ship_quests.calls
	ship_quests.changed.connect(_follow.bind(ship_quests))


func goal_progress(quest: Quest, index: int) -> float:
	return visit.progress(quest, index, _players()) if visit else super(quest, index)


func hand_in(quest: Quest, payer: Player, players: Array[Player]) -> bool:
	return visit != null and visit.hand_in(quest, payer, players)


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
func _follow(ship_quests: QuestLog) -> void:
	tracked = ship_quests.tracked
	emit_changed()
