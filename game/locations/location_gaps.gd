class_name LocationGaps
extends RefCounted
## The gaps of a generated location (`LocationBiome.Barrier.GAPS`, `GAPS_AND_WALLS`: crevasses,
## sinkholes, lava channels): ground lowered below the floor beside the open ground, in bands or
## round pits, a raised lip along their edges, and invisible walls behind the lips that stop
## players and aliens but not shots or sight, so nobody falls in. What fills them (lava, brine) is
## a flat surface over the gaps' grid squares; what stands along their edges (shard fences) a mesh
## drawn many times on the walls. Planned with the location (plain data, safe on a worker thread);
## `build` adds the walls, the fill and the fence.

## How high the walls along a gap's edge reach above the ground, in m.
const EDGE_WALL_HEIGHT: float = 4.0
## How far from the open ground pits reach, relative to the widest one (`gap_width`).
const PIT_REACH: float = 1.5
## How far apart the pits lie, relative to the widest one.
const PIT_SPACING: float = 2.6
## How far apart the fence's spikes stand along the walls, in m, how much they vary in size
## (smallest, largest) and lean (in degrees).
const FENCE_SPACING: float = 0.9
const FENCE_SCALE: Vector2 = Vector2(0.7, 1.4)
const FENCE_TILT: float = 18.0

## Grid points of a gap (1 = lowered), and the ones behind the walls (1 = a gap or its lip).
var gaps: PackedByteArray
var blocked: PackedByteArray
## The walls: from, to (location-local x, z) of each, one after the other.
var edge_lines: PackedVector2Array = []
## Height of the fill's surface (`LocationBiome.gap_fill`), location-local.
var fill_height: float = 0.0
## The fill's surface: a quad over every grid square with a gap's corner (two triangles each).
var _fill_vertices: PackedVector3Array = []

var _terrain: LocationTerrain
var _biome: LocationBiome
## Varies the gaps' widths.
var _widths: FastNoiseLite
## Where the pits lie (`LocationBiome.GapShape.PITS`; null for bands): the distance to the
## nearest pit's middle.
var _pits: FastNoiseLite
## The least width of a gap at each grid point (see `widen`); empty while there's none.
var _least: PackedFloat32Array
var _edge_faces: PackedVector3Array = []
## The fence's spikes (their transforms, standing on their base), by chunk.
var _fence: Dictionary[Vector2i, Array] = {}


func _init(
	terrain: LocationTerrain, biome: LocationBiome, widths: FastNoiseLite, pits: FastNoiseLite
) -> void:
	_terrain = terrain
	_biome = biome
	_widths = widths
	gaps.resize(terrain.heights.size())
	if pits:
		_pits = pits
		_pits.noise_type = FastNoiseLite.TYPE_CELLULAR
		_pits.fractal_type = FastNoiseLite.FRACTAL_NONE
		_pits.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		_pits.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		_pits.cellular_jitter = 0.8
		_pits.frequency = 1.0 / (biome.gap_width.y * PIT_SPACING)


## Makes the gaps at least `width` wide within `reach` m of `center` (location-local x, z): along
## a bridge, around a lava island or in a sinkhole field's pit.
func widen(center: Vector2, reach: float, width: float) -> void:
	if _least.is_empty():
		_least.resize(gaps.size())
	var low: Vector2i = Vector2i(_terrain.to_grid(center - Vector2.ONE * reach).floor()).maxi(0)
	var high: Vector2i = Vector2i(_terrain.to_grid(center + Vector2.ONE * reach).ceil()).mini(
		_terrain.cells
	)
	for z: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var at: Vector3 = _terrain.point(x, z)
			if center.distance_to(Vector2(at.x, at.z)) <= reach:
				var index: int = _terrain.index(x, z)
				_least[index] = maxf(_least[index], width)


## How much grid point `x`, `z` lies in a gap, `distance` m from the open ground: 1 inside, fading
## out towards its far side (where the ground comes back up, or the rock rises), 0 outside. Marks
## the gap's grid points.
func share(x: int, z: int, distance: float) -> float:
	if distance <= 0.0:
		return 0.0
	var index: int = _terrain.index(x, z)
	var at: Vector3 = _terrain.point(x, z)
	var noise: float = clampf(_widths.get_noise_2d(at.x, at.z) * 1.5 + 0.5, 0.0, 1.0)
	var width: float = lerpf(_biome.gap_width.x, _biome.gap_width.y, noise)
	var full: float = maxf(_biome.cliff_width, _terrain.cell * 1.5)
	var least: float = 0.0 if _least.is_empty() else _least[index]
	var inside: float = 0.0
	if _pits:
		# A round pit: `width` is its radius here.
		if distance < _biome.gap_width.y * PIT_REACH:
			var nearest: float = (_pits.get_noise_2d(at.x, at.z) + 1.0) / _pits.frequency
			if nearest < width:
				inside = 1.0 - smoothstep(width - full, width, nearest)
	else:
		least = maxf(least, width)
	if distance < least:
		inside = maxf(inside, 1.0 - smoothstep(least - full, least, distance))
	if inside > 0.0:
		gaps[index] = 1
	return inside


## Raises the lip along the gaps' edges (the ground next to a gap, also diagonally, so no grid
## square has both a gap's and a walkable corner) and blocks the gaps and their lips off.
func raise_lips() -> void:
	blocked = gaps.duplicate()
	var last: int = _terrain.cells
	for z: int in last + 1:
		for x: int in last + 1:
			if not gaps[_terrain.index(x, z)]:
				continue
			for nz: int in range(maxi(z - 1, 0), mini(z + 1, last) + 1):
				for nx: int in range(maxi(x - 1, 0), mini(x + 1, last) + 1):
					var index: int = _terrain.index(nx, nz)
					if not blocked[index]:
						blocked[index] = 1
						_terrain.heights[index] += _biome.lip_height


## Plans the walls along the edges, once the walkable ground (`reachable`) is known, the fill and
## the fence (drawing from `rng`).
func plan(reachable: PackedByteArray, rng: RandomNumberGenerator) -> void:
	_plan_edges(reachable)
	if _biome.gap_fill:
		_plan_fill()
	if _biome.fence:
		_plan_fence(rng)


## Adds the walls to `location` (a `GapEdges` body on `PhysicsLayers.WALKING_ONLY`), the fill
## (`GapFill`) and the fence (`Fence`, in chunks).
func build(location: Node3D) -> void:
	if not _fence.is_empty():
		_add_fence(location)
	if not _fill_vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _fill_vertices
		var normals := PackedVector3Array()
		normals.resize(_fill_vertices.size())
		normals.fill(Vector3.UP)
		arrays[Mesh.ARRAY_NORMAL] = normals
		var surface := ArrayMesh.new()
		surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var fill := MeshInstance3D.new()
		fill.name = "GapFill"
		fill.mesh = surface
		fill.material_override = _biome.gap_fill
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		location.add_child(fill)
		_fill_vertices.clear()
	if _edge_faces.is_empty():
		return
	var edges := StaticBody3D.new()
	edges.name = "GapEdges"
	edges.collision_layer = PhysicsLayers.WALKING_ONLY
	edges.collision_mask = 0
	var faces := ConcavePolygonShape3D.new()
	faces.backface_collision = true
	faces.set_faces(_edge_faces)
	var shape := CollisionShape3D.new()
	shape.shape = faces
	edges.add_child(shape)
	location.add_child(edges)
	_edge_faces.clear()


## The fill's surface, `LocationBiome.gap_fill_level` above the gaps' level bottom: over every
## grid square with a gap's corner (where the ground rises above it, the ground hides it).
func _plan_fill() -> void:
	fill_height = -_biome.gap_depth + _biome.gap_fill_level
	var row: int = _terrain.cells + 1
	var cell: float = _terrain.cell
	for z: int in _terrain.cells:
		for x: int in _terrain.cells:
			var first: int = _terrain.index(x, z)
			if not (gaps[first] or gaps[first + 1] or gaps[first + row] or gaps[first + row + 1]):
				continue
			var corner := Vector3(
				_terrain.origin.x + x * cell, fill_height, _terrain.origin.y + z * cell
			)
			var along_x := Vector3(cell, 0.0, 0.0)
			var along_z := Vector3(0.0, 0.0, cell)
			_fill_vertices.append_array(
				[
					corner,
					corner + along_x,
					corner + along_z,
					corner + along_x,
					corner + along_x + along_z,
					corner + along_z
				]
			)


## The fence's spikes along the walls, about `FENCE_SPACING` apart, each of its own size and lean,
## in chunks so the ones out of view are culled.
func _plan_fence(rng: RandomNumberGenerator) -> void:
	var chunk_size: float = GeneratedLocation.CHUNK_CELLS * _terrain.cell
	for i: int in range(0, edge_lines.size(), 2):
		var from: Vector2 = edge_lines[i]
		var to: Vector2 = edge_lines[i + 1]
		var count: int = maxi(1, roundi(from.distance_to(to) / FENCE_SPACING))
		for k: int in count:
			var at: Vector2 = from.lerp(to, (k + rng.randf_range(0.2, 0.8)) / count)
			var grown: float = rng.randf_range(FENCE_SCALE.x, FENCE_SCALE.y)
			var tilt: float = deg_to_rad(rng.randf_range(-FENCE_TILT, FENCE_TILT))
			var turn := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, tilt)
			var size := Vector3(grown, grown * rng.randf_range(0.8, 1.3), grown)
			var placed := Transform3D(
				turn.scaled(size), Vector3(at.x, _terrain.height_at(at.x, at.y) - 0.1, at.y)
			)
			var chunk := Vector2i(((at - _terrain.origin) / chunk_size).floor())
			if not _fence.has(chunk):
				_fence[chunk] = []
			_fence[chunk].append(placed)


## Adds the fence's chunks under a `Fence` node of `location`, each spike standing on its base.
func _add_fence(location: Node3D) -> void:
	var fence := Node3D.new()
	fence.name = "Fence"
	location.add_child(fence)
	var base: float = -_biome.fence.get_aabb().position.y
	for chunk: Vector2i in _fence:
		var spikes: Array = _fence[chunk]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _biome.fence
		multimesh.instance_count = spikes.size()
		for i: int in spikes.size():
			var placed: Transform3D = spikes[i]
			placed.origin += placed.basis.y * base
			multimesh.set_instance_transform(i, placed)
		var instance := MultiMeshInstance3D.new()
		instance.name = "Fence%d_%d" % [chunk.x, chunk.y]
		instance.multimesh = multimesh
		fence.add_child(instance)
	_fence.clear()


## The walls, where walkable ground (`reachable`) meets a lip: in every grid square with a reachable
## and a blocked corner, from the middle of one of its sides to the middle of another, cutting the
## blocked corners off, so they cross every step from a walkable grid point onto a blocked one.
func _plan_edges(reachable: PackedByteArray) -> void:
	# The middles of a grid square's sides: side `s` runs from its corner `s` to the next (corners:
	# its first grid point, the next along x, the far one, the next along z).
	var middles: Array[Vector2] = [
		Vector2(0.5, 0.0), Vector2(1.0, 0.5), Vector2(0.5, 1.0), Vector2(0.0, 0.5)
	]
	var row: int = _terrain.cells + 1
	for z: int in _terrain.cells:
		for x: int in _terrain.cells:
			var first: int = _terrain.index(x, z)
			var corners: PackedInt32Array = [first, first + 1, first + row + 1, first + row]
			var closed: int = 0
			var reached: bool = false
			for corner: int in 4:
				closed |= blocked[corners[corner]] << corner
				reached = reached or reachable[corners[corner]] == 1
			if closed == 0 or closed == 15 or not reached:
				continue
			var lowest: float = INF
			var highest: float = -INF
			for index: int in corners:
				lowest = minf(lowest, _terrain.heights[index])
				highest = maxf(highest, _terrain.heights[index])
			var origin: Vector2 = _terrain.origin + Vector2(x, z) * _terrain.cell
			for wall: Vector2i in _walls_in(closed):
				var from: Vector2 = origin + middles[wall.x] * _terrain.cell
				var to: Vector2 = origin + middles[wall.y] * _terrain.cell
				edge_lines.append_array([from, to])
				var low_from := Vector3(from.x, lowest - 1.0, from.y)
				var low_to := Vector3(to.x, lowest - 1.0, to.y)
				var high_from := Vector3(from.x, highest + EDGE_WALL_HEIGHT, from.y)
				var high_to := Vector3(to.x, highest + EDGE_WALL_HEIGHT, to.y)
				_edge_faces.append_array([low_from, low_to, high_to, low_from, high_to, high_from])


## The walls in a grid square whose `closed` corners (bits) are blocked: pairs of the sides they
## run between (where a blocked corner meets an open one). Two blocked corners across from each
## other are each cut off on their own.
static func _walls_in(closed: int) -> Array[Vector2i]:
	var crossed: Array[int] = []
	for side: int in 4:
		if ((closed >> side) ^ (closed >> ((side + 1) % 4))) & 1:
			crossed.append(side)
	if crossed.size() == 2:
		return [Vector2i(crossed[0], crossed[1])]
	var walls: Array[Vector2i] = []
	for corner: int in 4:
		if (closed >> corner) & 1:
			walls.append(Vector2i((corner + 3) % 4, corner))
	return walls
