class_name QuestSite
extends Node3D
## Where a quest's site is reached (see `ReachGoal`): at the quest anchor of its map part (else its
## middle). The first player who comes within `RADIUS` reaches it (`reached`), once per visit.

## Emitted when a player first comes close enough.
signal reached(player: Player)

## How close a player must come, in m. TBD (playtest).
const RADIUS: float = 5.0
## How often the distance to the players is checked, in s.
const CHECK: float = 0.25

var is_reached: bool = false

var _check_left: float = 0.0


func _process(delta: float) -> void:
	_check_left -= delta
	if is_reached or _check_left > 0.0:
		return
	_check_left = CHECK
	for node: Node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if player and not player.dead and _is_near(player):
			is_reached = true
			reached.emit(player)
			return


func _is_near(player: Player) -> bool:
	return player.global_position.distance_to(global_position) <= RADIUS
