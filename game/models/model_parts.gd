class_name ModelParts
extends RefCounted
## Takes meshes out of an imported model (.glb) without instancing it. A model kit holds many
## parts (e.g. all rock variants) of which a scene needs one or a few; instancing the whole model
## and freeing it again costs time and can leave its meshes drawing.


## The mesh of the node named `part`, or null. Its transform is ignored: meant for parts that sit
## at their model's origin, like scatter meshes.
static func mesh(model: PackedScene, part: StringName) -> Mesh:
	var state: SceneState = model.get_state()
	for i: int in state.get_node_count():
		if state.get_node_name(i) == part:
			return _property(state, i, &"mesh") as Mesh
	return null


## New mesh instances for the direct children of the node named `parent`, in model order, with
## their names, meshes and transforms (relative to `parent`). Children without a mesh (e.g. marker
## empties) are left out.
static func child_parts(model: PackedScene, parent: StringName) -> Array[MeshInstance3D]:
	var state: SceneState = model.get_state()
	var parts: Array[MeshInstance3D] = []
	for i: int in state.get_node_count():
		var parent_path: NodePath = state.get_node_path(i, true)
		var count: int = parent_path.get_name_count()
		if count == 0 or parent_path.get_name(count - 1) != parent:
			continue
		var found := _property(state, i, &"mesh") as Mesh
		if not found:
			continue
		var part := MeshInstance3D.new()
		part.name = state.get_node_name(i)
		part.mesh = found
		var placed: Variant = _property(state, i, &"transform")
		if placed is Transform3D:
			part.transform = placed
		parts.append(part)
	return parts


static func _property(state: SceneState, node: int, property: StringName) -> Variant:
	for p: int in state.get_node_property_count(node):
		if state.get_node_property_name(node, p) == property:
			return state.get_node_property_value(node, p)
	return null
