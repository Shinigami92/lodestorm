class_name HoloTable
extends Node3D
## The table in the middle of the bridge. Its projector shows a hologram of a mission location:
## a scaled-down copy of the location's meshes, spinning slowly above the table, with landmarks
## (where the ship stands) in a brighter color. Players stand around it to see where they're going.

const LOCATION_COLOR := Color(0.3, 0.85, 1.0)
const LANDMARK_COLOR := Color(1.0, 0.85, 0.35)

## How far the hologram reaches from the table's center, in m.
@export var radius: float = 2.4
## Stretches heights, so flat locations still show their rocks and nests. TBD (playtest).
@export var height_scale: float = 1.5
## Turns per second.
@export var spin_speed: float = 0.03

var _location_material: ShaderMaterial = _material(LOCATION_COLOR)
var _landmark_material: ShaderMaterial = _material(LANDMARK_COLOR)

@onready var _hologram: Node3D = $Hologram
@onready var _content: Node3D = $Hologram/Content


func _process(delta: float) -> void:
	_hologram.rotate_y(TAU * spin_speed * delta)


## Shows `location` (as it is right now) and the `landmarks` in it as a hologram.
func show_location(location: Node3D, landmarks: Array[Node3D] = []) -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var to_location: Transform3D = location.global_transform.affine_inverse()
	var parts: Array[MeshInstance3D] = []
	_copy_meshes(location, to_location, _location_material, parts)
	for landmark: Node3D in landmarks:
		_copy_meshes(landmark, to_location, _landmark_material, parts)
	if parts.is_empty():
		return

	var bounds: AABB = parts[0].transform * parts[0].mesh.get_aabb()
	for part: MeshInstance3D in parts:
		bounds = bounds.merge(part.transform * part.mesh.get_aabb())
	var center: Vector3 = bounds.get_center()
	var reach: float = 0.0
	for part: MeshInstance3D in parts:
		var box: AABB = part.mesh.get_aabb()
		for i: int in 8:
			var corner: Vector3 = part.transform * box.get_endpoint(i) - center
			reach = maxf(reach, Vector2(corner.x, corner.z).length())
	var scale_xz: float = radius / maxf(reach, 0.001)
	var scale_y: float = scale_xz * height_scale
	_content.transform = Transform3D(
		Basis.from_scale(Vector3(scale_xz, scale_y, scale_xz)),
		Vector3(-center.x * scale_xz, -bounds.position.y * scale_y, -center.z * scale_xz)
	)
	for part: MeshInstance3D in parts:
		_content.add_child(part)


func _copy_meshes(
	root: Node3D, to_location: Transform3D, material: Material, parts: Array[MeshInstance3D]
) -> void:
	var sources: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		sources.append(root)
	for source: MeshInstance3D in sources:
		if not source.mesh or not source.is_visible_in_tree():
			continue
		var part := MeshInstance3D.new()
		part.mesh = source.mesh
		part.transform = to_location * source.global_transform
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parts.append(part)


static func _material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/hologram.gdshader")
	material.set_shader_parameter(&"color", color)
	return material
