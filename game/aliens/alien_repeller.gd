class_name AlienRepeller
extends Node3D
## An old survey repeller (see docs/design/crew.md, Hollis out there): aliens don't come within
## `radius` of it (one inside walks out again), and nobody inside is their prey (players, miners).
## A post at Hollis' camp, and the hand repeller he carries on his way to the ship. Values TBD
## (playtest).

## Every repeller in the tree.
const GROUP: StringName = &"alien_repellers"

## How far it keeps aliens off, in m (on the ground).
@export var radius: float = 12.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	remove_from_group(GROUP)


## The repeller in `tree` whose reach covers `point` (global, on the ground), or null.
static func covering(tree: SceneTree, point: Vector3) -> AlienRepeller:
	if not tree:
		return null
	for node: Node in tree.get_nodes_in_group(GROUP):
		var repeller := node as AlienRepeller
		if not repeller or not repeller.is_visible_in_tree():
			continue
		var offset: Vector3 = point - repeller.global_position
		if Vector2(offset.x, offset.z).length() <= repeller.radius:
			return repeller
	return null
