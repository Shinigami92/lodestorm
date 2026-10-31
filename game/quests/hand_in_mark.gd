class_name HandInMark
extends QuestMark
## Marks an NPC waiting out in a location for a step to be handed in (a meeting, see
## `QuestVisit.meetings`, e.g. Hollis at his camp): lit while it's the tracked quest's active step
## and its goals are all done out here (with what the players carry), so the beam and the suit ring
## lead back to them.


## A mark for `meeting` of `in_visit` on `target` (the NPC), above their feet.
static func on_person(
	target: Node3D, meeting: QuestVisit.Entry, in_visit: QuestVisit
) -> HandInMark:
	var mark := HandInMark.new()
	mark.name = "HandInMark"
	mark.entry = meeting
	mark.visit = in_visit
	target.add_child(mark)
	return mark


func is_lit() -> bool:
	if not is_open or not visit or not visit.is_tracked(entry):
		return false
	if visit.meeting_for(entry.quest) != entry:
		return false
	var players: Array[Player] = []
	for node: Node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if player and not player.dead:
			players.append(player)
	return visit.is_ready(entry.quest, players)
