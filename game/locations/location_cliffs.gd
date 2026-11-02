class_name LocationCliffs
extends RefCounted
## Rock chunks set against the cliffs of a generated location (`LocationBiome.cliff_dressing`),
## so the rock the heightfield raises beside the open ground gets jagged faces: where walkable
## ground meets rock that rises at least `MIN_RISE` within `REACH` grid points, one chunk about
## every `SPACING` m along the cliff's foot, its face towards the open ground, sized to the cliff.
## Never on the camera's side (it rises low there, the camera looks over it). Only looks: the
## heightfield keeps blocking. Planned with the location (plain data, safe on a worker thread);
## `build` adds the nodes, in chunks so the parts out of view are culled. All values TBD
## (playtest).

## How far apart the chunks stand along a cliff, about, in m.
const SPACING: float = 7.0
## The least a cliff rises within `REACH` grid points for a chunk, in m.
const MIN_RISE: float = 3.0
const REACH: int = 2
## How far a chunk's face stands out in front of the cliff's foot, in m (it hides the seam).
const FRONT_OUT: float = 0.3
## How much higher or lower than the cliff a chunk may reach (share of its height).
const FIT: Vector2 = Vector2(0.5, 0.85)
## How far a chunk turns away from facing the open ground straight, in degrees.
const TURN: float = 20.0
## Where it looks for the cliff: the grid's eight directions.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
]

## Planned chunks: x, z of the foot (location-local), the way towards the open ground (an angle
## around up), the cliff's rise, a variant's index and a random 0..1 for its size.
var _feet: Array[Vector4] = []
var _sizes: PackedFloat32Array = []
var _variants: PackedInt32Array = []
var _types: Array[ScatterType] = []


## Where the chunks of `types` stand: at the foot of the cliffs along the `reachable` ground (not
## the rock flagged in `camera_side`).
func plan(
	rng: RandomNumberGenerator,
	terrain: LocationTerrain,
	types: Array[ScatterType],
	reachable: PackedByteArray,
	camera_side: PackedByteArray
) -> void:
	_types = types.filter(func(type: ScatterType) -> bool: return type.has_mesh())
	if _types.is_empty():
		return
	var taken: Dictionary[Vector2i, bool] = {}
	for z: int in range(REACH, terrain.cells + 1 - REACH):
		for x: int in range(REACH, terrain.cells + 1 - REACH):
			if reachable[terrain.index(x, z)] != 1:
				continue
			var at: Vector3 = terrain.point(x, z)
			var key := Vector2i((Vector2(at.x, at.z) / SPACING).floor())
			if taken.has(key):
				continue
			var uphill := Vector2.ZERO
			var rise: float = 0.0
			for offset: Vector2i in DIRECTIONS:
				var far: Vector2i = Vector2i(x, z) + offset * REACH
				var index: int = terrain.index(far.x, far.y)
				if reachable[index] == 1 or (not camera_side.is_empty() and camera_side[index]):
					continue
				var climb: float = terrain.get_height(far.x, far.y) - at.y
				if climb >= MIN_RISE:
					uphill += Vector2(offset).normalized() * climb
					rise = maxf(rise, climb)
			if rise < MIN_RISE:
				continue
			taken[key] = true
			var facing: float = (-uphill).angle() + deg_to_rad(rng.randf_range(-TURN, TURN))
			_feet.append(Vector4(at.x, at.z, facing, rise))
			_sizes.append(rng.randf())
			_variants.append(rng.randi() % _types.size())


## Adds the planned chunks under a `Cliffs` node of `location`, by variant and chunk.
func build(location: GeneratedLocation) -> void:
	if _feet.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Cliffs"
	location.add_child(holder)
	var terrain: LocationTerrain = location.terrain
	var chunk_size: float = GeneratedLocation.CHUNK_CELLS * terrain.cell
	var by_chunk: Dictionary[Vector3i, Array] = {}
	var placed: Array[Transform3D] = placements(terrain)
	for i: int in placed.size():
		var foot := Vector2(_feet[i].x, _feet[i].y)
		var chunk := Vector2i(((foot - terrain.origin) / chunk_size).floor())
		var key := Vector3i(chunk.x, chunk.y, _variants[i])
		if not by_chunk.has(key):
			by_chunk[key] = []
		by_chunk[key].append(placed[i])
	for key: Vector3i in by_chunk:
		var type: ScatterType = _types[key.z]
		var in_chunk: Array = by_chunk[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = type.get_mesh()
		multimesh.instance_count = in_chunk.size()
		for i: int in in_chunk.size():
			var at: Transform3D = in_chunk[i]
			multimesh.set_instance_transform(i, at)
		var instance := MultiMeshInstance3D.new()
		instance.name = "%s%d_%d" % [type.display_name.to_pascal_case(), key.x, key.y]
		instance.multimesh = multimesh
		holder.add_child(instance)
	_feet.clear()


## Where each planned chunk stands on `terrain` (loads the meshes, for their size): sized to its
## cliff, its face (the model's +z) turned towards the open ground and set back so its front
## stands `FRONT_OUT` in front of the foot.
func placements(terrain: LocationTerrain) -> Array[Transform3D]:
	var placed: Array[Transform3D] = []
	for i: int in _feet.size():
		var foot: Vector4 = _feet[i]
		var type: ScatterType = _types[_variants[i]]
		var bounds: AABB = type.get_mesh().get_aabb()
		var tall: float = maxf(bounds.end.y, 0.1)
		var grown: float = clampf(
			foot.w / tall * lerpf(FIT.x, FIT.y, _sizes[i]), type.min_scale, type.max_scale
		)
		var out := Vector3(cos(foot.z), 0.0, sin(foot.z))
		var turn := Basis(Vector3.UP, atan2(out.x, out.z))
		var origin := Vector3(foot.x, 0.0, foot.y) - out * (bounds.end.z * grown - FRONT_OUT)
		origin.y = terrain.height_at(foot.x, foot.y) - type.sink * grown
		placed.append(Transform3D(turn.scaled(Vector3.ONE * grown), origin))
	return placed
