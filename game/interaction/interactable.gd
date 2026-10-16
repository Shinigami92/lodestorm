class_name Interactable
extends Node3D
## Something a player uses with `interact` while standing close to it (buttons, later terminals
## and vendors). The player shows which one it would use: an optional child `Highlight` node is
## visible while this is the target.

## Emitted when a player uses it.
signal used(player: Player)

const GROUP: StringName = &"interactables"

## How close (horizontally, in m) a player must be to use it.
@export var interact_range: float = 1.5

## Disabled interactables can't be targeted or used.
var enabled: bool = true

## Shows the `Highlight` child.
var highlighted: bool = false:
	set(value):
		highlighted = value
		if _highlight:
			_highlight.visible = value

@onready var _highlight: Node3D = get_node_or_null(^"Highlight") as Node3D


func _ready() -> void:
	add_to_group(GROUP)
	highlighted = highlighted


func use(player: Player) -> void:
	if enabled:
		used.emit(player)


## The enabled interactable closest to `from` that is within its range, or null.
static func nearest(tree: SceneTree, from: Vector3) -> Interactable:
	var nearest_target: Interactable = null
	var nearest_distance: float = INF
	for target: Interactable in tree.get_nodes_in_group(GROUP):
		var offset: Vector3 = target.global_position - from
		var distance: float = Vector2(offset.x, offset.z).length()
		if target.enabled and distance <= target.interact_range and distance < nearest_distance:
			nearest_target = target
			nearest_distance = distance
	return nearest_target
