class_name QuestPointer
extends RingPointer
## Points to the nearest thing the tracked quest still needs in the location (its nearest lit
## `QuestMark`: its site, a crate with its fragment, one of its nests, its item) while the local
## player is outside: the suit ring draws it on its edge in the quests' amber. It hides within
## `min_distance` of it and once nothing is left here.

const ALPHA: float = 0.85

## How close (m, horizontally) the mark may be before the arrow hides. TBD (playtest).
var min_distance: float = 12.0
## The mark it points to, or null.
var target: QuestMark


func _init() -> void:
	arrow = Vector2(0.96, 0.3)
	priority = 1
	color = Color(QuestMark.COLOR, ALPHA)


func _ready() -> void:
	visible = false


func _physics_process(_delta: float) -> void:
	target = _find_target()
	visible = target != null
	if visible:
		# Runs after the player turned this tick, so the arrow keeps pointing at the mark.
		point_along(target.global_position - global_position)


func _find_target() -> QuestMark:
	if not holder or holder.fallen or not holder.local:
		return null
	var ship: Ship = Ship.nearest(get_tree(), global_position)
	if ship and ship.is_aboard(holder):
		return null
	var nearest: QuestMark = null
	var nearest_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(QuestMark.GROUP):
		var mark := node as QuestMark
		if not mark.is_lit():
			continue
		var offset: Vector3 = mark.global_position - global_position
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance < nearest_distance:
			nearest = mark
			nearest_distance = distance
	return nearest if nearest and nearest_distance > min_distance else null
