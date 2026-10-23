class_name OreScanner
extends Node3D
## The ore scanner (a skill): points to the nearest ore node within `reach` (the skill's value)
## that isn't dry while the local player is outside, with or without a miner on it: its -Z turns
## towards the node, and the suit ring draws it as a small arrow on its edge in `color`, the ore's
## color. It hides within `min_distance` of the node. Like the arrow back to the ship, but smaller.

const ALPHA: float = 0.75

## How far it looks for ore nodes (m); 0: off (the skill isn't learned).
var reach: float = 0.0
## How close (m) a node may be before the arrow hides (the miner placing range: it's in reach).
var min_distance: float = 2.5
## The node it points to, or null.
var target: OreNode
## The arrow's color.
var color := Color.WHITE


func _ready() -> void:
	visible = false


func _physics_process(_delta: float) -> void:
	target = _find_target()
	visible = target != null
	if not visible:
		return
	var offset: Vector3 = target.global_position - global_position
	# Runs after the player turned this tick, so the arrow keeps pointing at the node.
	global_basis = Basis(Vector3.UP, atan2(-offset.x, -offset.z))
	color = Color(target.ore_type.color, ALPHA)


func _find_target() -> OreNode:
	var player := get_parent() as Player
	if reach <= 0.0 or not player or player.dead or not player.local:
		return null
	var ship: Ship = Ship.nearest(get_tree(), global_position)
	if ship and ship.is_aboard(player):
		return null
	var nearest: OreNode = null
	var nearest_distance: float = reach
	for node: OreNode in get_tree().get_nodes_in_group(OreNode.GROUP):
		var offset: Vector3 = node.global_position - global_position
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance <= nearest_distance and not node.is_dry():
			nearest = node
			nearest_distance = distance
	return nearest if nearest and nearest_distance > min_distance else null
