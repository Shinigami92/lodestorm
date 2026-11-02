class_name LocationFarRing
extends RefCounted
## The land beyond a generated location's rim: one cheap mesh in a ring around the map, in the
## biome's shapes (mesas, ridges, slabs, or flat ice where it has no rock) and its textures seen
## from afar, fading into the haze, so a VR player looking over the cliffs sees the land go on
## instead of an edge. It starts at the rim's height and falls to the far land's within the first
## stretch. Only looks (no collision, no shadows, not in the holo table's hologram). Planned with
## the location (plain data, safe on a worker thread); `build` adds the node. All values TBD
## (playtest).

## Distances of the rings of vertices beyond the map's edge, in m (closer together near it).
const RINGS: PackedFloat32Array = [
	0.0, 6.0, 16.0, 32.0, 56.0, 90.0, 140.0, 210.0, 300.0, 420.0, 580.0, 800.0, 1100.0, 1500.0
]
## Vertices along the map's edge, per side.
const PER_SIDE: int = 40
## Over how many m beyond the edge the rim's height gives way to the far land's.
const BLEND: float = 160.0
## How far the land's outer rim sinks below the floor, in m (hidden in the haze).
const OUTER_SINK: float = 30.0
## The far land's features' width, in m.
const FEATURE_SIZE: float = 260.0
## How much higher than the biome's walls the far rock rises.
const RELIEF_SCALE: float = 1.4
const SHADER: Shader = preload("res://assets/shaders/far_land.gdshader")

var _arrays: Array = []


## The mesh around `terrain` (a square), in `biome`'s shapes, drawn from `rng`.
func plan(rng: RandomNumberGenerator, terrain: LocationTerrain, biome: LocationBiome) -> void:
	var noise: FastNoiseLite = GeneratedLocation.make_noise(rng, 1.0 / FEATURE_SIZE, 3)
	var detail: FastNoiseLite = GeneratedLocation.make_noise(rng, 1.0 / 45.0, 2)
	var area: Rect2 = terrain.rect()
	var center: Vector2 = area.get_center()
	var half: float = area.size.x * 0.5
	var edge: PackedVector2Array = _edge(area)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for at_edge: Vector2 in edge:
		var out: Vector2 = (at_edge - center).normalized()
		var inside: Vector2 = at_edge.clamp(area.position, area.end)
		var rim: float = terrain.height_at(inside.x, inside.y)
		for ring: int in RINGS.size():
			var distance: float = RINGS[ring]
			var at: Vector2 = at_edge + out * distance
			var far: float = _height(biome, noise, detail, at)
			var blend: float = smoothstep(0.0, BLEND, distance)
			var height: float = lerpf(rim, far, blend)
			height -= (
				smoothstep(RINGS[RINGS.size() - 3], RINGS[RINGS.size() - 1], distance)
				* (OUTER_SINK + far)
			)
			vertices.append(Vector3(at.x, height, at.y))
			# R: how high (rock is lighter, like the map's), A: how far out (0 at the edge).
			colors.append(Color(smoothstep(0.0, _relief(biome), height), 0.0, 0.0, distance / half))
	var count: int = RINGS.size()
	var indices := PackedInt32Array()
	for i: int in edge.size():
		var a: int = i * count
		var b: int = ((i + 1) % edge.size()) * count
		for ring: int in count - 1:
			indices.append_array(
				[a + ring, a + ring + 1, b + ring, b + ring, a + ring + 1, b + ring + 1]
			)
	_arrays.resize(Mesh.ARRAY_MAX)
	_arrays[Mesh.ARRAY_VERTEX] = vertices
	_arrays[Mesh.ARRAY_COLOR] = colors
	_arrays[Mesh.ARRAY_INDEX] = indices


## Adds the mesh as `FarRing` to `location`, textured like `biome`'s ground.
func build(location: Node3D, biome: LocationBiome) -> void:
	if _arrays.is_empty():
		return
	var tool := SurfaceTool.new()
	tool.create_from_arrays(_arrays, Mesh.PRIMITIVE_TRIANGLES)
	tool.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "FarRing"
	mesh.mesh = tool.commit()
	mesh.material_override = material_for(biome)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Not part of the map: the holo table's hologram would shrink the map to fit it.
	mesh.add_to_group(HoloTable.HIDDEN_GROUP)
	location.add_child(mesh)
	_arrays.clear()


## The far land's material for `biome`: its ground's textures (from the terrain shader's material)
## sampled once each, without the close-up blending.
static func material_for(biome: LocationBiome) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var ground := biome.ground_material as ShaderMaterial
	if ground:
		for parameter: StringName in [
			&"ground_albedo",
			&"ground_tint",
			&"rock_albedo",
			&"rock_tint",
			&"ground_tile",
			&"rock_tile"
		]:
			var value: Variant = ground.get_shader_parameter(parameter)
			if value != null:
				material.set_shader_parameter(parameter, value)
	material.set_shader_parameter(&"low_tint", biome.low_ground_tint)
	return material


## Points along the square's edge, counterclockwise from its corner.
func _edge(area: Rect2) -> PackedVector2Array:
	var corners: Array[Vector2] = [
		area.position,
		Vector2(area.end.x, area.position.y),
		area.end,
		Vector2(area.position.x, area.end.y),
	]
	var points := PackedVector2Array()
	for side: int in 4:
		for i: int in PER_SIDE:
			points.append(corners[side].lerp(corners[(side + 1) % 4], float(i) / PER_SIDE))
	return points


## How high the far land rises at most.
func _relief(biome: LocationBiome) -> float:
	if not biome.has_walls():
		return maxf(biome.wall_height, 4.0)
	return (biome.wall_height + biome.rock_relief) * RELIEF_SCALE


## The far land's height at `at`, in the biome's shape.
func _height(
	biome: LocationBiome, noise: FastNoiseLite, detail: FastNoiseLite, at: Vector2
) -> float:
	var n: float = clampf(noise.get_noise_2dv(at) * 0.5 + 0.5, 0.0, 1.0)
	var relief: float = _relief(biome)
	var rough: float = detail.get_noise_2dv(at)
	if not biome.has_walls():
		# Wide, flat sheets with low pressure ridges.
		return smoothstep(0.55, 0.8, n) * relief * 0.6 + rough * 1.0
	match biome.rock_shape:
		LocationBiome.RockShape.RIDGES:
			var ridge: float = 1.0 - absf(noise.get_noise_2d(at.x * 1.7, at.y * 1.7))
			return pow(ridge, 3.0) * relief * smoothstep(0.2, 0.6, n) + rough * 2.0
		LocationBiome.RockShape.SLABS:
			var step: float = maxf(biome.plateau_step, 1.0) * 2.0
			return floorf(n * relief / step) * step + rough * 0.5
	# Mesas: flat tops in layers, steep sides.
	var layers: float = maxf(biome.plateau_step, 1.0)
	var raw: float = smoothstep(0.35, 0.75, n) * relief
	var stepped: float = floorf(raw / layers) * layers
	var lip: float = smoothstep(0.0, 0.25, fmod(raw, layers) / layers)
	return stepped + lip * layers * 0.3 + rough * 1.0
