class_name OreNode
extends Node3D
## A deposit of one ore type that a single miner can be placed on. Shows a ring while it's the
## spot a player would place their next miner on.

const GROUP: StringName = &"ore_nodes"

@export var ore_type: OreType

## The miner placed on this node, or null.
var miner: Miner

## Shows the placement ring.
var highlighted: bool = false:
	set(value):
		highlighted = value
		if is_node_ready():
			_highlight.visible = value

@onready var _mount: Marker3D = $MinerMount
@onready var _crystals: Node3D = $Crystals
@onready var _highlight: MeshInstance3D = $Highlight


func _ready() -> void:
	add_to_group(GROUP)
	for crystal: Node in _crystals.get_children():
		(crystal as MeshInstance3D).material_override = ore_type.get_material()
	_highlight.visible = highlighted


func is_free() -> bool:
	return not is_instance_valid(miner)


## Places a new miner from `miner_scene` on this node and returns it, or null if occupied.
func place_miner(miner_scene: PackedScene) -> Miner:
	if not is_free():
		return null
	miner = miner_scene.instantiate() as Miner
	miner.ore_type = ore_type
	_mount.add_child(miner)
	return miner


## The free ore node closest to `from` within `max_distance` (horizontally), or null.
static func nearest_free(tree: SceneTree, from: Vector3, max_distance: float) -> OreNode:
	var nearest: OreNode = null
	var nearest_distance: float = max_distance
	for node: OreNode in tree.get_nodes_in_group(GROUP):
		var offset: Vector3 = node.global_position - from
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance <= nearest_distance and node.is_free():
			nearest = node
			nearest_distance = distance
	return nearest
