class_name LocationScatter
extends RefCounted
## The plants and rocks of a generated location: where each of its biome's `ScatterType`s grows
## (on a jittered grid, in patches, off steep ground and the places the location keeps free, the
## blocking ones apart from each other), cut into chunks so the parts out of view are culled.
## Planned with the location (plain data, safe on a worker thread); `build` adds the nodes.

## Tallest plant or rock that grows on the rock on the camera's side, in m (taller ones would hide
## the open ground behind the low ledge there).
const CAMERA_SIDE_SCATTER: float = 1.0

## Planned chunks: type, name and placements (`Transform3D`s) of each.
var _types: Array[ScatterType] = []
var _names: PackedStringArray = []
var _placements: Array[Array] = []


## Where the plants and rocks of `location`'s biome grow, by type and chunk.
func plan(rng: RandomNumberGenerator, location: GeneratedLocation) -> void:
	var terrain: LocationTerrain = location.terrain
	var chunk_size: float = GeneratedLocation.CHUNK_CELLS * location.cell
	var blockers: Array[Vector4] = []
	for type: ScatterType in location.biome.scatter:
		var by_chunk: Dictionary[Vector2i, Array] = {}
		for placed: Transform3D in _transforms(rng, location, type, blockers):
			var chunk: Vector2i = Vector2i(
				((Vector2(placed.origin.x, placed.origin.z) - terrain.origin) / chunk_size).floor()
			)
			if not by_chunk.has(chunk):
				by_chunk[chunk] = []
			by_chunk[chunk].append(placed)
		for chunk: Vector2i in by_chunk:
			_types.append(type)
			_names.append("%s%d_%d" % [type.display_name.to_pascal_case(), chunk.x, chunk.y])
			_placements.append(by_chunk[chunk])


## Adds the planned chunks under a `Scatter` node of `location`.
func build(location: Node3D) -> void:
	var scatter := Node3D.new()
	scatter.name = "Scatter"
	location.add_child(scatter)
	for i: int in _types.size():
		_add_chunk(scatter, _types[i], _names[i], _placements[i])
	_placements.clear()


## Where `type` grows: on a jittered grid, thinned out by patches, steep ground and the places
## `location` keeps free. Blocking ones keep their distance from each other (`blockers`: x, z,
## radius, spacing).
func _transforms(
	rng: RandomNumberGenerator,
	location: GeneratedLocation,
	type: ScatterType,
	blockers: Array[Vector4]
) -> Array[Transform3D]:
	var placed: Array[Transform3D] = []
	if type.density <= 0.0 or not type.has_mesh():
		return placed
	var terrain: LocationTerrain = location.terrain
	var spacing: float = sqrt(100.0 / type.density)
	var patches: FastNoiseLite = GeneratedLocation.make_noise(rng, 1.0 / type.patch_size, 2)
	var steps: int = floori(terrain.size() / spacing)
	for row: int in steps:
		for column: int in steps:
			var at: Vector2 = (
				terrain.origin
				+ (Vector2(column, row) + Vector2(rng.randf(), rng.randf())) * spacing
			)
			var patch: float = smoothstep(-0.05, 0.15, patches.get_noise_2dv(at))
			if rng.randf() > lerpf(1.0, patch, type.clustering):
				continue
			var grown: float = rng.randf_range(type.min_scale, type.max_scale)
			var radius: float = type.blocking_radius * grown
			var tall: bool = type.blocking_height * grown > CAMERA_SIDE_SCATTER
			if not _fits(location, at, type, radius, blockers, tall):
				continue
			if not type.area_kinds.is_empty() and not location.is_in_area_of(at, type.area_kinds):
				continue
			if radius > 0.0:
				blockers.append(Vector4(at.x, at.y, radius, type.spacing))
			var tilt: float = deg_to_rad(rng.randf_range(-type.max_tilt, type.max_tilt))
			var turn := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, tilt)
			var height: float = terrain.height_at(at.x, at.y) - type.sink * grown
			placed.append(
				Transform3D(turn.scaled(Vector3.ONE * grown), Vector3(at.x, height, at.y))
			)
	return placed


## Whether a `type` of `radius` (0: not blocking) can grow at `at`: where `location` lets it (see
## `GeneratedLocation.lets_grow`), on ground no steeper than its `max_slope`, away from other
## `blockers` (by the larger spacing of the two).
func _fits(
	location: GeneratedLocation,
	at: Vector2,
	type: ScatterType,
	radius: float,
	blockers: Array[Vector4],
	tall: bool
) -> bool:
	if not location.lets_grow(at, radius, tall, type.on_barrier):
		return false
	var grid: Vector2i = Vector2i(location.terrain.to_grid(at).round())
	if location.terrain.slope(grid.x, grid.y) > type.max_slope:
		return false
	if radius > 0.0:
		for blocker: Vector4 in blockers:
			var apart: float = blocker.z + radius + maxf(blocker.w, type.spacing)
			if at.distance_squared_to(Vector2(blocker.x, blocker.y)) < apart * apart:
				return false
	return true


func _add_chunk(parent: Node3D, type: ScatterType, chunk_name: String, transforms: Array) -> void:
	if not type.get_mesh():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = type.get_mesh()
	multimesh.instance_count = transforms.size()
	for i: int in transforms.size():
		var placed: Transform3D = transforms[i]
		multimesh.set_instance_transform(i, placed)
	var instance := MultiMeshInstance3D.new()
	instance.name = chunk_name
	instance.multimesh = multimesh
	instance.visibility_range_end = type.visibility_range
	# Fade in and out instead of popping, a whole chunk at a time.
	instance.visibility_range_end_margin = type.visibility_range * 0.25
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not type.cast_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	if type.blocking_radius <= 0.0:
		return
	var body := StaticBody3D.new()
	body.name = instance.name + "Body"
	for placed: Transform3D in transforms:
		var grown: float = placed.basis.get_scale().x
		var cylinder := CylinderShape3D.new()
		cylinder.radius = type.blocking_radius * grown
		cylinder.height = type.blocking_height * grown
		var shape := CollisionShape3D.new()
		shape.shape = cylinder
		# The collider stands on the ground, wherever the mesh's origin is.
		var ground: float = placed.origin.y + type.sink * grown
		shape.position = Vector3(placed.origin.x, ground + cylinder.height * 0.5, placed.origin.z)
		body.add_child(shape)
	parent.add_child(body)
