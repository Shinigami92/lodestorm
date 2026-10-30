class_name Interactable
extends Node3D
## Something a player uses with `interact` while standing close to it (buttons, later terminals
## and vendors). The player shows which one it would use: an optional child `Highlight` node is
## visible while this is the target (a marking: decals leave it out, `RenderLayers.MARKINGS`).

## Emitted when a player uses it.
signal used(player: Player)

const GROUP: StringName = &"interactables"
## How far above or below a player's feet it may be (in m): the ship's decks are 4.5 apart, so what
## stands on the other deck is out of reach.
const REACH_HEIGHT: float = 2.0

## How close (horizontally, in m) a player must be to use it: to its `footprint`'s edge, or to it.
@export var interact_range: float = 1.5
## The object it belongs to on the floor, a rectangle centered on it (along its x and z, in m), so
## players use it from any side; none (a point) when zero. Round objects: a point at their center
## with their radius in `interact_range`.
@export var footprint: Vector2 = Vector2.ZERO

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
	if _highlight:
		RenderLayers.put(_highlight, RenderLayers.MARKINGS)
	highlighted = highlighted


func use(player: Player) -> void:
	if enabled:
		used.emit(player)


## How far `from` is from its `footprint` (or from it), horizontally, in m.
func distance_to(from: Vector3) -> float:
	var local: Vector3 = global_transform.affine_inverse() * from
	var outside := Vector2(
		maxf(absf(local.x) - footprint.x * 0.5, 0.0), maxf(absf(local.z) - footprint.y * 0.5, 0.0)
	)
	return outside.length()


## The enabled interactable closest to `from` that is within its range and `REACH_HEIGHT`, or null.
static func nearest(tree: SceneTree, from: Vector3) -> Interactable:
	var nearest_target: Interactable = null
	var nearest_distance: float = INF
	for target: Interactable in tree.get_nodes_in_group(GROUP):
		if absf(target.global_position.y - from.y) > REACH_HEIGHT:
			continue
		var distance: float = target.distance_to(from)
		if target.enabled and distance <= target.interact_range and distance < nearest_distance:
			nearest_target = target
			nearest_distance = distance
	return nearest_target
