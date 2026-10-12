class_name LocationTerrain
extends RefCounted
## The ground of a generated location as a height field: a square grid of heights, `cell` m apart,
## starting at `origin` (location-local x, z). Each grid square is split into two triangles along
## the same diagonal everywhere, so `height_at` matches the ground mesh and its collision exactly.

## Distance between grid points, in m.
var cell: float
## Grid squares per side.
var cells: int
## Location-local x, z of the first grid point.
var origin: Vector2
## Heights, row by row (z), `cells + 1` per row.
var heights: PackedFloat32Array


func _init(p_origin: Vector2, p_cells: int, p_cell: float) -> void:
	origin = p_origin
	cells = p_cells
	cell = p_cell
	heights.resize((cells + 1) * (cells + 1))


## Edge length of the whole ground, in m.
func size() -> float:
	return cells * cell


## Location-local area the ground covers.
func rect() -> Rect2:
	return Rect2(origin, Vector2.ONE * size())


func index(x: int, z: int) -> int:
	return z * (cells + 1) + x


func get_height(x: int, z: int) -> float:
	return heights[index(clampi(x, 0, cells), clampi(z, 0, cells))]


func set_height(x: int, z: int, height: float) -> void:
	heights[index(x, z)] = height


## Location-local position of grid point `x`, `z`.
func point(x: int, z: int) -> Vector3:
	return Vector3(origin.x + x * cell, get_height(x, z), origin.y + z * cell)


## Grid coordinates (fractional) of a location-local x, z.
func to_grid(local: Vector2) -> Vector2:
	return (local - origin) / cell


## Ground height at location-local `x`, `z` (clamped to the ground's edges).
func height_at(x: float, z: float) -> float:
	var grid: Vector2 = to_grid(Vector2(x, z)).clamp(Vector2.ZERO, Vector2.ONE * cells)
	var gx: int = mini(int(grid.x), cells - 1)
	var gz: int = mini(int(grid.y), cells - 1)
	var tx: float = grid.x - gx
	var tz: float = grid.y - gz
	var a: float = get_height(gx, gz)
	var b: float = get_height(gx + 1, gz)
	var c: float = get_height(gx, gz + 1)
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	var d: float = get_height(gx + 1, gz + 1)
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


## Smooth surface normal at grid point `x`, `z`.
func normal(x: int, z: int) -> Vector3:
	return (
		Vector3(
			get_height(x - 1, z) - get_height(x + 1, z),
			2.0 * cell,
			get_height(x, z - 1) - get_height(x, z + 1)
		)
		. normalized()
	)


## Steepest slope around grid point `x`, `z` towards its neighbors, in rise per m.
func slope(x: int, z: int) -> float:
	var height: float = get_height(x, z)
	var steepest: float = 0.0
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		steepest = maxf(steepest, absf(get_height(x + offset.x, z + offset.y) - height))
	return steepest / cell


## Highest ground within `reach` grid points of each grid point (a square around it), row by row
## like `heights`.
func highest_around(reach: int) -> PackedFloat32Array:
	var side: int = cells + 1
	var rows := PackedFloat32Array()
	rows.resize(heights.size())
	for z: int in side:
		for x: int in side:
			var highest: float = -INF
			for nx: int in range(maxi(x - reach, 0), mini(x + reach, cells) + 1):
				highest = maxf(highest, heights[z * side + nx])
			rows[z * side + x] = highest
	var result := PackedFloat32Array()
	result.resize(heights.size())
	for z: int in side:
		for x: int in side:
			var highest: float = -INF
			for nz: int in range(maxi(z - reach, 0), mini(z + reach, cells) + 1):
				highest = maxf(highest, rows[nz * side + x])
			result[z * side + x] = highest
	return result


## Grid squares that can be walked from `start` (location-local x, z) without climbing a slope
## steeper than `max_slope` (rise per m) between neighboring grid points. 1 = reachable.
func reachable_from(start: Vector2, max_slope: float) -> PackedByteArray:
	var reached := PackedByteArray()
	reached.resize(heights.size())
	var grid: Vector2 = to_grid(start).round()
	var first: int = index(clampi(int(grid.x), 0, cells), clampi(int(grid.y), 0, cells))
	var queue := PackedInt32Array([first])
	reached[first] = 1
	var max_rise: float = max_slope * cell
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		var x: int = current % (cells + 1)
		var z: int = current / (cells + 1)
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + offset.x
			var nz: int = z + offset.y
			if nx < 0 or nz < 0 or nx > cells or nz > cells:
				continue
			var next: int = index(nx, nz)
			if reached[next] or absf(heights[next] - heights[current]) > max_rise:
				continue
			reached[next] = 1
			queue.append(next)
	return reached


## Pulls the ground towards `height` around `center` (location-local x, z): flat within `radius`,
## blending back to the old ground over `falloff` m.
func flatten(center: Vector2, radius: float, falloff: float, height: float) -> void:
	_flatten_area(center, Vector2(radius, radius), falloff, height, true)


## Like `flatten`, for the axis-aligned rectangle `area`.
func flatten_rect(area: Rect2, falloff: float, height: float) -> void:
	_flatten_area(area.get_center(), area.size * 0.5, falloff, height, false)


## Mesh of the grid squares from `from` (inclusive) to `to` (exclusive), its vertex colors from
## `paint` (called with a grid point's position and normal, returns its color).
func build_mesh(from: Vector2i, to: Vector2i, paint: Callable) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, build_arrays(from, to, paint))
	return mesh


## The surface arrays of `build_mesh`, without creating the mesh (safe on a worker thread).
func build_arrays(from: Vector2i, to: Vector2i, paint: Callable) -> Array:
	var width: int = to.x - from.x + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for z: int in range(from.y, to.y + 1):
		for x: int in range(from.x, to.x + 1):
			var position: Vector3 = point(x, z)
			var up: Vector3 = normal(x, z)
			vertices.append(position)
			normals.append(up)
			var color: Color = paint.call(position, up)
			colors.append(color)
	var indices := PackedInt32Array()
	for z: int in to.y - from.y:
		for x: int in to.x - from.x:
			var a: int = z * width + x
			var b: int = a + 1
			var c: int = a + width
			var d: int = c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Collision triangles of the same grid squares as `build_mesh`.
func build_shape(from: Vector2i, to: Vector2i) -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(build_faces(from, to))
	return shape


## The triangles of `build_shape`, without creating the shape (safe on a worker thread).
func build_faces(from: Vector2i, to: Vector2i) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for z: int in range(from.y, to.y):
		for x: int in range(from.x, to.x):
			var a: Vector3 = point(x, z)
			var b: Vector3 = point(x + 1, z)
			var c: Vector3 = point(x, z + 1)
			var d: Vector3 = point(x + 1, z + 1)
			faces.append_array([a, b, c, b, d, c])
	return faces


func _flatten_area(
	center: Vector2, half: Vector2, falloff: float, height: float, round_area: bool
) -> void:
	var reach: Vector2 = half + Vector2.ONE * falloff
	var low: Vector2 = to_grid(center - reach).floor()
	var high: Vector2 = to_grid(center + reach).ceil()
	for z: int in range(maxi(int(low.y), 0), mini(int(high.y), cells) + 1):
		for x: int in range(maxi(int(low.x), 0), mini(int(high.x), cells) + 1):
			var offset: Vector2 = (Vector2(x, z) * cell + origin - center).abs()
			var outside: float
			if round_area:
				outside = offset.length() - half.x
			else:
				outside = (offset - half).max(Vector2.ZERO).length()
			var weight: float = 1.0 - smoothstep(0.0, maxf(falloff, 0.001), outside)
			if weight > 0.0:
				set_height(x, z, lerpf(get_height(x, z), height, weight))
