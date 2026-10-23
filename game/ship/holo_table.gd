class_name HoloTable
extends Node3D
## The table in the middle of the bridge. Its projector shows a hologram of a mission location:
## a scaled-down copy of the location's meshes above the table, with landmarks (where the ship
## stands) in a brighter color. It doesn't turn: it lies the way the ship stands in the location
## (the ramp side to the right like aboard), so what lies beside the ship in the hologram lies
## beside it outside. Players stand around it to see where they're going.
## Every ore node shows as a beam in its ore's color (`Hologram/Markers`), so players see where
## the ores lie and plan their route; at the hologram's scale the deposits themselves are specks.
## Parts of the location in `LANDMARK_GROUP` (points of interest) show in the landmark color too,
## each with a thicker beam in it so it reads at the hologram's scale; the ones in `HIDDEN_GROUP`
## (crates, so finding them stays a discovery) don't show.
## The location may still be outside the tree (a mission's location prepared before the flight).

const LOCATION_COLOR := Color(0.3, 0.85, 1.0)
const LANDMARK_COLOR := Color(1.0, 0.85, 0.35)
const LANDMARK_GROUP: StringName = &"hologram_landmarks"
const HIDDEN_GROUP: StringName = &"hidden_in_hologram"

## How far the hologram reaches from the table's center, in m.
@export var radius: float = 2.4
## Stretches heights, so flat locations still show their rocks and nests. TBD (playtest).
@export var height_scale: float = 1.5
## Size of the ore beams (radius, height), in m of the hologram.
@export var marker_size: Vector2 = Vector2(0.025, 0.3)
## Size of the beams of the landmarks in the location (radius, height), in m of the hologram.
@export var landmark_marker_size: Vector2 = Vector2(0.06, 0.4)

var _location_material: ShaderMaterial = hologram_material(LOCATION_COLOR)
var _landmark_material: ShaderMaterial = hologram_material(LANDMARK_COLOR)
var _marker_materials: Dictionary[OreType, ShaderMaterial] = {}

@onready var _content: Node3D = $Hologram/Content
@onready var _markers: Node3D = $Hologram/Markers


## Shows `location` (as it is right now) and the `landmarks` in it as a hologram; null clears it.
## `origin`: where the location stands in the world (or will stand, if it's outside the tree).
func show_location(
	location: Node3D, landmarks: Array[Node3D] = [], origin: Transform3D = Transform3D.IDENTITY
) -> void:
	for parent: Node3D in [_content, _markers]:
		# Freed right away: they're only copies, and the next location may follow in the same frame.
		for child: Node in parent.get_children():
			child.free()
	if not location:
		return
	if location.is_inside_tree():
		origin = location.global_transform
	var parts: Array[MeshInstance3D] = _copied(location, location, _location_material)
	var to_location: Transform3D = origin.affine_inverse()
	for landmark: Node3D in landmarks:
		for part: MeshInstance3D in _copied(landmark, landmark, _landmark_material):
			part.transform = to_location * landmark.global_transform * part.transform
			parts.append(part)
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
	_add_markers(location)
	RenderLayers.put($Hologram, RenderLayers.HOLOGRAMS)


## Shows or hides the location hologram (the navigator shows the star system or a globe instead).
func show_hologram(shown: bool) -> void:
	($Hologram as Node3D).visible = shown


## Scales the location hologram (the navigator grows it in while zooming into a landing site).
func set_hologram_scale(value: float) -> void:
	($Hologram as Node3D).scale = Vector3.ONE * maxf(value, 0.001)


## The ore beams in the hologram (one per ore node, in its ore's color).
func get_markers() -> Array[MeshInstance3D]:
	return _beams(false)


## The landmarks' beams in the hologram (one per point of interest, in the landmark color).
func get_landmark_markers() -> Array[MeshInstance3D]:
	return _beams(true)


func _beams(landmarks: bool) -> Array[MeshInstance3D]:
	var markers: Array[MeshInstance3D] = []
	for marker: MeshInstance3D in _markers.get_children():
		if marker.has_meta(&"landmark") == landmarks:
			markers.append(marker)
	return markers


func _add_markers(location: Node3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = marker_size.x
	mesh.bottom_radius = marker_size.x
	mesh.height = marker_size.y
	mesh.radial_segments = 8
	mesh.rings = 1
	var landmark_mesh := CylinderMesh.new()
	landmark_mesh.top_radius = landmark_marker_size.x
	landmark_mesh.bottom_radius = landmark_marker_size.x
	landmark_mesh.height = landmark_marker_size.y
	landmark_mesh.radial_segments = 12
	landmark_mesh.rings = 1
	for node: Node in location.find_children("*", "Node3D", true, false):
		if node.is_in_group(LANDMARK_GROUP) and _is_shown(node as Node3D, location):
			var beam := MeshInstance3D.new()
			beam.mesh = landmark_mesh
			beam.material_override = _landmark_material
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			beam.set_meta(&"landmark", true)
			var spot: Vector3 = _content.transform * _relative(node as Node3D, location).origin
			beam.position = spot + Vector3.UP * landmark_marker_size.y * 0.5
			_markers.add_child(beam)
			continue
		var ore := node as OreNode
		if not ore or not ore.ore_type:
			continue
		var marker := MeshInstance3D.new()
		marker.mesh = mesh
		marker.material_override = _marker_material(ore.ore_type)
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var at: Vector3 = _content.transform * _relative(ore, location).origin
		marker.position = at + Vector3.UP * marker_size.y * 0.5
		_markers.add_child(marker)


func _marker_material(ore_type: OreType) -> ShaderMaterial:
	if not _marker_materials.has(ore_type):
		var material: ShaderMaterial = hologram_material(ore_type.color)
		material.set_shader_parameter(&"energy", 3.0)
		_marker_materials[ore_type] = material
	return _marker_materials[ore_type]


## Copies of the visible meshes under `root` (and `root` itself), placed relative to `space`.
func _copied(root: Node3D, space: Node3D, material: Material) -> Array[MeshInstance3D]:
	var parts: Array[MeshInstance3D] = []
	var sources: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		sources.append(root)
	for source: MeshInstance3D in sources:
		if not source.mesh or not _is_shown(source, space):
			continue
		var part := MeshInstance3D.new()
		part.mesh = source.mesh
		part.transform = _relative(source, space)
		part.material_override = (
			_landmark_material if _is_in(source, space, LANDMARK_GROUP) else material
		)
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parts.append(part)
	return parts


## `node`'s transform in `space` (one of its ancestors, or itself); works outside the tree too.
static func _relative(node: Node3D, space: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var at: Node = node
	while at and at != space:
		var spatial := at as Node3D
		if spatial:
			result = spatial.transform * result
		at = at.get_parent()
	return result


## Whether `node` and its parents up to `space` are visible (and not hidden from the hologram).
static func _is_shown(node: Node3D, space: Node3D) -> bool:
	var at: Node = node
	while at:
		var spatial := at as Node3D
		if spatial and (not spatial.visible or spatial.is_in_group(HIDDEN_GROUP)):
			return false
		if at == space:
			return true
		at = at.get_parent()
	return true


## Whether `node` or one of its parents up to `space` is in `group`.
static func _is_in(node: Node, space: Node3D, group: StringName) -> bool:
	var at: Node = node
	while at:
		if at.is_in_group(group):
			return true
		if at == space:
			return false
		at = at.get_parent()
	return false


## A hologram material in `color` (also for the navigator's hologram).
static func hologram_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/hologram.gdshader")
	material.set_shader_parameter(&"color", color)
	return material
