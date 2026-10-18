class_name LocationGaps
extends RefCounted
## The gaps of a generated location (`LocationBiome.Barrier.GAPS`: crevasses so far): ground
## lowered below the floor beside the open ground, a raised lip along their edges, and invisible
## walls behind the lips that stop players and aliens but not shots or sight, so nobody falls in.
## Planned with the location (plain data, safe on a worker thread); `build` adds the walls.

## How high the walls along a gap's edge reach above the ground, in m.
const EDGE_WALL_HEIGHT: float = 4.0

## Grid points of a gap (1 = lowered), and the ones behind the walls (1 = a gap or its lip).
var gaps: PackedByteArray
var blocked: PackedByteArray
## The walls: from, to (location-local x, z) of each, one after the other.
var edge_lines: PackedVector2Array = []

var _terrain: LocationTerrain
var _biome: LocationBiome
## Varies the gaps' widths.
var _widths: FastNoiseLite
var _edge_faces: PackedVector3Array = []


func _init(terrain: LocationTerrain, biome: LocationBiome, widths: FastNoiseLite) -> void:
	_terrain = terrain
	_biome = biome
	_widths = widths
	gaps.resize(terrain.heights.size())


## How far the ground at grid point `x`, `z` lies below the floor (0 outside the gaps), `distance`
## m from the open ground where `walls` of a cliff would stand (see `GeneratedLocation._walls`): a
## sheer drop beside the open ground; beyond the gap's width the ground comes back up to the
## floor's level (land nobody reaches). Marks the gap's grid points.
func depth(x: int, z: int, distance: float, walls: float) -> float:
	var at: Vector3 = _terrain.point(x, z)
	var noise: float = clampf(_widths.get_noise_2d(at.x, at.z) * 1.5 + 0.5, 0.0, 1.0)
	var width: float = lerpf(_biome.gap_width.x, _biome.gap_width.y, noise)
	if distance <= 0.0 or distance >= width:
		return 0.0
	gaps[_terrain.index(x, z)] = 1
	var full: float = maxf(_biome.cliff_width, _terrain.cell * 1.5)
	var up: float = smoothstep(width - full, width, distance)
	return _biome.gap_depth * walls * (1.0 - up)


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


## The walls, where walkable ground (`reachable`) meets a lip: in every grid square with a reachable
## and a blocked corner, from the middle of one of its sides to the middle of another, cutting the
## blocked corners off, so they cross every step from a walkable grid point onto a blocked one.
func plan_edges(reachable: PackedByteArray) -> void:
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


## Adds the walls to `location`: a `GapEdges` body on `PhysicsLayers.WALKING_ONLY`.
func build(location: Node3D) -> void:
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
