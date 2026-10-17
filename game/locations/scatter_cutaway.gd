class_name ScatterCutaway
extends Node3D
## Hides the plants and rocks on the rock where the camera's cut-away presses the ground down
## (`IsoCameraRig.cutaway_press`; they'd float above it) and shows them again once it moves on.
## Only the scatter on the rock: on the open ground the cut-away leaves the ground where it is.

## How much the ground under a thing must be pressed down before it's hidden.
const HIDE_FROM: float = 0.05
## How far the cut-away must move (its target or camera, in m) before the scatter is checked again.
const RECHECK_DISTANCE: float = 0.25

var _meshes: Array[MultiMesh] = []
## Each mesh's placements (local transforms of its instances).
var _placements: Array[Array] = []
## Each mesh's center and how far its instances reach from it (x, y, z, reach), local.
var _bounds: Array[Vector4] = []
## Each mesh's hidden instances.
var _hidden: Array[PackedInt32Array] = []
var _last_target: Vector4 = Vector4.INF
var _last_camera: Vector3 = Vector3.INF


## Watches the instances of `mesh`, placed at `placements` (local transforms).
func watch(mesh: MultiMesh, placements: Array) -> void:
	var center := Vector3.ZERO
	for placed: Transform3D in placements:
		center += placed.origin
	center /= maxf(placements.size(), 1.0)
	var reach: float = 0.0
	for placed: Transform3D in placements:
		reach = maxf(reach, placed.origin.distance_to(center))
	_meshes.append(mesh)
	_placements.append(placements)
	_bounds.append(Vector4(center.x, center.y, center.z, reach))
	_hidden.append(PackedInt32Array())


## Whether instance `index` of `mesh` is hidden right now.
func is_hidden(mesh: MultiMesh, index: int) -> bool:
	var i: int = _meshes.find(mesh)
	return i >= 0 and index in _hidden[i]


## How many instances are hidden right now.
func hidden_count() -> int:
	var count: int = 0
	for hidden: PackedInt32Array in _hidden:
		count += hidden.size()
	return count


func _process(_delta: float) -> void:
	var target: Vector4 = IsoCameraRig.cutaway_target
	var camera: Vector3 = IsoCameraRig.cutaway_camera
	var moved: bool = (
		absf(target.w - _last_target.w) > 0.001
		or (
			Vector3(target.x, target.y, target.z).distance_to(
				Vector3(_last_target.x, _last_target.y, _last_target.z)
			)
			> RECHECK_DISTANCE
		)
		or camera.distance_to(_last_camera) > RECHECK_DISTANCE
	)
	if not moved:
		return
	_last_target = target
	_last_camera = camera
	for i: int in _meshes.size():
		_update(i, _near_cutaway(i))


## Whether mesh `i`'s instances may lie in the cut-away (its bounds come near the camera's line).
func _near_cutaway(i: int) -> bool:
	var target: Vector4 = IsoCameraRig.cutaway_target
	if target.w <= 0.0:
		return false
	var bounds: Vector4 = _bounds[i]
	var center: Vector3 = global_transform * Vector3(bounds.x, bounds.y, bounds.z)
	var aim := Vector3(target.x, target.y, target.z)
	var closest: Vector3 = Geometry3D.get_closest_point_to_segment(
		center, aim, IsoCameraRig.cutaway_camera
	)
	return center.distance_to(closest) < bounds.w + target.w


## Hides mesh `i`'s instances where the ground is pressed down (all shown when `near` is false).
func _update(i: int, near: bool) -> void:
	var mesh: MultiMesh = _meshes[i]
	var placements: Array = _placements[i]
	var hidden: PackedInt32Array = _hidden[i]
	if not near:
		for index: int in hidden:
			var placed: Transform3D = placements[index]
			mesh.set_instance_transform(index, placed)
		_hidden[i] = PackedInt32Array()
		return
	var now_hidden := PackedInt32Array()
	for index: int in placements.size():
		var placed: Transform3D = placements[index]
		var pressed: float = IsoCameraRig.cutaway_press(global_transform * placed.origin)
		if pressed > HIDE_FROM:
			now_hidden.append(index)
			if index not in hidden:
				mesh.set_instance_transform(
					index, Transform3D(Basis.from_scale(Vector3.ZERO), placed.origin)
				)
		elif index in hidden:
			mesh.set_instance_transform(index, placed)
	_hidden[i] = now_hidden
