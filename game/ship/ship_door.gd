class_name ShipDoor
extends Node3D
## A sliding door aboard that never gets in the way (docs/planned/ship-interior.md): it opens while
## someone walking (a player, an NPC on its way: `OPENERS`) is within `reach` (in `open_time`; at a
## run that's done before they arrive) and closes once nobody has been near for `close_delay`. It
## has no collision, so even a moving door never blocks anyone. Two leaves slide apart along x into
## the wall; the door stands in a wall along x (its z the wall's thickness), its origin at the
## opening's bottom middle. In a wall cut away for the camera, the door is cut like its wall: the
## part up to the stub stays in sight, the part above it (`lead` set) goes with the wall.

## Whoever walks through doors joins this group: players, and NPCs that walk (a colonist on its
## route); people standing at their posts don't, so they never hold a door open.
const OPENERS: StringName = &"opens_doors"
const LEAF_DEPTH: float = 0.12

## The opening's size.
@export var width: float = 3.0
@export var height: float = 3.0
@export var reach: float = 5.0
@export var open_time: float = 0.4
@export var close_delay: float = 1.5
@export var open_sound: Sound = preload("res://assets/audio/sfx/mission/door.tres")
@export var leaf_material: Material = preload("res://game/ship/shell/shell_dark.tres")
## The part above a cut wall's stub moves with the door below it: silent, it never looks for anyone.
@export var lead: ShipDoor
## Where the leaves start: the part above a stub starts at the stub's top.
@export var bottom: float = 0.0

## 0 closed, 1 open.
var openness: float = 0.0

var _alone_for: float = INF
var _leaves: Array[MeshInstance3D] = []


func _ready() -> void:
	for side: float in [-1.0, 1.0]:
		var leaf := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width / 2.0, height - bottom, LEAF_DEPTH)
		box.material = leaf_material
		leaf.mesh = box
		leaf.name = "Left" if side < 0.0 else "Right"
		leaf.layers = RenderLayers.INTERIOR
		add_child(leaf)
		_leaves.append(leaf)
	_place_leaves()


func _physics_process(delta: float) -> void:
	if lead:
		openness = lead.openness
		_place_leaves()
		return
	_alone_for = 0.0 if is_someone_near() else _alone_for + delta
	var wanted: float = 1.0 if _alone_for < close_delay else 0.0
	if wanted > 0.0 and openness == 0.0 and open_sound:
		Sfx.play_at(open_sound, global_position + Vector3.UP * height / 2.0)
	openness = move_toward(openness, wanted, delta / open_time)
	_place_leaves()


## Whether one of the `OPENERS` stands within `reach` of the opening's bottom middle.
func is_someone_near() -> bool:
	for walker: Node in get_tree().get_nodes_in_group(OPENERS):
		if (walker as Node3D).global_position.distance_to(global_position) < reach:
			return true
	return false


func _place_leaves() -> void:
	for i: int in _leaves.size():
		var side: float = -1.0 if i == 0 else 1.0
		var closed_x: float = side * width / 4.0
		var x: float = closed_x + side * openness * width / 2.0
		_leaves[i].position = Vector3(x, (bottom + height) / 2.0, 0.0)
