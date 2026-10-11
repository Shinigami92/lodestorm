class_name CameraZone
extends Area3D
## While the camera's target is inside, the camera looks at this zone's `Focus` instead of the
## target, e.g. to fit a whole room on screen (the ship's shooting range).

const GROUP: StringName = &"camera_zones"

@onready var _focus: Node3D = $Focus


func _ready() -> void:
	add_to_group(GROUP)


## Where the camera looks while its target is inside.
func focus_position() -> Vector3:
	return _focus.global_position


## The zone that `body` is in, or null.
static func containing(tree: SceneTree, body: PhysicsBody3D) -> CameraZone:
	for zone: CameraZone in tree.get_nodes_in_group(GROUP):
		if zone.overlaps_body(body):
			return zone
	return null
