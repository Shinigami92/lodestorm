class_name LocationPasses
extends RefCounted
## The ground along a generated location's passes: the lanes that blocking plants and rocks, ore
## nodes and nests keep free (along every pass, up to the middle of the areas it joins), the ramps
## between areas at different levels (terraces) and the trodden paths down the trails
## (`LocationBiome.PassStyle.TRAILS`). Plain data, planned with the location. All values greybox,
## TBD (playtest).

## Half the width of a lane, plus the room the widest blocking thing needs, in m.
const LANE_HALF_WIDTH: float = 5.0
## How far into an area (relative to its radius) a lane leads; the middle is open enough.
const LANE_FREE_MIDDLE: float = 0.6
## How steep the ramps between terraces are (rise per m).
const TERRACE_RAMP_SLOPE: float = 0.3
## Half the width of a trail's trodden path, and over how many m its edge fades out, in m.
const PATH_HALF_WIDTH: float = 1.5
const PATH_EDGE: float = 1.0
## The trodden path's tint: darker, packed soil.
const PATH_TINT := Color(0.62, 0.55, 0.48)

## Grid points on a lane (1 = keep free).
var lanes: PackedByteArray
## How much each grid point lies on a trail's trodden path: 1 on it, fading out over its edge;
## empty without trails.
var paths: PackedFloat32Array

var _terrain: LocationTerrain
var _biome: LocationBiome
var _layout: LocationLayout


func _init(terrain: LocationTerrain, biome: LocationBiome, layout: LocationLayout) -> void:
	_terrain = terrain
	_biome = biome
	_layout = layout
	lanes.resize(terrain.heights.size())
	if biome.pass_style == LocationBiome.PassStyle.TRAILS:
		paths.resize(terrain.heights.size())


## Marks the lanes (and the trails' paths) along every pass, and the lane from the ramp's exit to
## the landing yard (`yard`: its center).
func mark(ramp_exit: Vector2, yard: Vector2) -> void:
	_mark_lane(ramp_exit, yard)
	for way: LocationLayout.Pass in _layout.passes:
		var ends: Array[LocationLayout.Area] = [_layout.areas[way.from], _layout.areas[way.to]]
		for i: int in range(1, way.points.size()):
			if _in_middle(way.points[i], ends):
				continue
			_mark_lane(way.points[i - 1], way.points[i])
			if not paths.is_empty():
				_mark_path(way.points[i - 1], way.points[i])


## How much location-local `at` lies on a trail's trodden path (0 without trails).
func path_at(at: Vector2) -> float:
	if paths.is_empty():
		return 0.0
	var grid: Vector2i = Vector2i(_terrain.to_grid(at).round()).clamp(
		Vector2i.ZERO, Vector2i.ONE * _terrain.cells
	)
	return paths[_terrain.index(grid.x, grid.y)]


## Lays the ramp along `way` between areas at different levels (terraces) into `levels`: the higher
## area's level up to where the pass leaves its outline (`bends`: how the outlines wobble), then
## down (`TERRACE_RAMP_SLOPE`) to the lower area's, which it reaches into when the two are close
## (`in_areas`: the areas' openness). Measured along the pass, so the ramp keeps its slope however
## the outlines wobble.
func lay_ramp(
	levels: PackedFloat32Array,
	way: LocationLayout.Pass,
	bends: PackedFloat32Array,
	in_areas: PackedFloat32Array
) -> void:
	var from: LocationLayout.Area = _layout.areas[way.from]
	var to: LocationLayout.Area = _layout.areas[way.to]
	var drop: float = absf(from.level - to.level)
	if drop <= 0.0:
		return
	var high: LocationLayout.Area = from if from.level > to.level else to
	# How far along the pass each point lies, from the higher end.
	var count: int = way.points.size()
	var arcs := PackedFloat32Array()
	arcs.resize(count)
	for i: int in range(1, count):
		arcs[i] = arcs[i - 1] + way.points[i].distance_to(way.points[i - 1])
	var total: float = arcs[count - 1]
	if high == to:
		for i: int in count:
			arcs[i] = total - arcs[i]
	var leaves: float = total
	for i: int in count:
		var at: Vector2 = way.points[i]
		var grid: Vector2i = Vector2i(_terrain.to_grid(at).round()).clamp(
			Vector2i.ZERO, Vector2i.ONE * _terrain.cells
		)
		var bend: float = bends[_terrain.index(grid.x, grid.y)]
		if at.distance_to(high.center) > high.radius * (1.0 + bend * GeneratedLocation.AREA_WOBBLE):
			leaves = minf(leaves, arcs[i])
	var length: float = drop / TERRACE_RAMP_SLOPE
	var half: float = way.width * 0.5 * (1.0 + _biome.pass_wobble)
	var low_corner: Vector2 = Vector2.INF
	var high_corner: Vector2 = -Vector2.INF
	for at: Vector2 in way.points:
		low_corner = low_corner.min(at)
		high_corner = high_corner.max(at)
	var low: Vector2i = Vector2i(_terrain.to_grid(low_corner - Vector2.ONE * half).floor()).maxi(0)
	var top: Vector2i = Vector2i(_terrain.to_grid(high_corner + Vector2.ONE * half).ceil()).mini(
		_terrain.cells
	)
	for z: int in range(low.y, top.y + 1):
		for x: int in range(low.x, top.x + 1):
			var at: Vector2 = _ground(x, z)
			var nearest: float = INF
			var along: float = 0.0
			for i: int in range(1, count):
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
					at, way.points[i - 1], way.points[i]
				)
				var distance: float = at.distance_to(closest)
				if distance < nearest:
					nearest = distance
					var part: float = closest.distance_to(way.points[i - 1])
					along = (
						arcs[i - 1]
						+ (
							(arcs[i] - arcs[i - 1])
							* part
							/ maxf(way.points[i].distance_to(way.points[i - 1]), 0.001)
						)
					)
			if nearest > half:
				continue
			var index: int = _terrain.index(x, z)
			var level: float = high.level - drop * clampf((along - leaves) / length, 0.0, 1.0)
			levels[index] = maxf(levels[index], level) if in_areas[index] > 0.0 else level


## Whether `at` lies in the middle of one of `areas`: open enough to walk around anything there,
## so the lanes end before it.
func _in_middle(at: Vector2, areas: Array[LocationLayout.Area]) -> bool:
	for area: LocationLayout.Area in areas:
		if at.distance_to(area.center) < area.radius * LANE_FREE_MIDDLE:
			return true
	return false


## Marks the grid points within `LANE_HALF_WIDTH` of the line from `from` to `to`.
func _mark_lane(from: Vector2, to: Vector2) -> void:
	for point: Vector2i in _grid_near(from, to, LANE_HALF_WIDTH):
		var at: Vector2 = _ground(point.x, point.y)
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(at, from, to)
		if at.distance_to(closest) <= LANE_HALF_WIDTH:
			lanes[_terrain.index(point.x, point.y)] = 1


## Marks the trodden path along the line from `from` to `to`.
func _mark_path(from: Vector2, to: Vector2) -> void:
	var reach: float = PATH_HALF_WIDTH + PATH_EDGE
	for point: Vector2i in _grid_near(from, to, reach):
		var at: Vector2 = _ground(point.x, point.y)
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(at, from, to)
		var share: float = 1.0 - smoothstep(PATH_HALF_WIDTH, reach, at.distance_to(closest))
		var index: int = _terrain.index(point.x, point.y)
		paths[index] = maxf(paths[index], share)


## The grid points in the box around the line from `from` to `to`, grown by `reach`.
func _grid_near(from: Vector2, to: Vector2, reach: float) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var low: Vector2 = _terrain.to_grid(from.min(to) - Vector2.ONE * reach).floor()
	var high: Vector2 = _terrain.to_grid(from.max(to) + Vector2.ONE * reach).ceil()
	for z: int in range(maxi(int(low.y), 0), mini(int(high.y), _terrain.cells) + 1):
		for x: int in range(maxi(int(low.x), 0), mini(int(high.x), _terrain.cells) + 1):
			points.append(Vector2i(x, z))
	return points


## Location-local x, z of grid point `x`, `z`.
func _ground(x: int, z: int) -> Vector2:
	return Vector2(_terrain.origin.x + x * _terrain.cell, _terrain.origin.y + z * _terrain.cell)
