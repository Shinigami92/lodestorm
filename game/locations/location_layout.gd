class_name LocationLayout
extends RefCounted
## The plan of a generated location as a graph: open areas (basins, crossroads, dead ends with rich
## ore, nest hollows, plateaus, craters) joined by winding passes, with high rock nobody can climb
## everywhere else. The first area is the landing yard in front of the ship's ramp. Every visit
## lays out a new graph from the seed; `GeneratedLocation` carves it into the ground. The passes
## form a tree plus a few loops, and never cross each other. Plain data, so it can be made on a
## worker thread. All values are greybox, TBD (playtest).

enum Kind { LANDING, BASIN, CROSSROADS, ORE_POCKET, NEST_HOLLOW, PLATEAU, CRATER }

## Distance between a pass's points, in m.
const PASS_STEP: float = 2.0
## Largest sideways bend of a pass, relative to its length.
const MAX_BEND: float = 0.2
## Longest pass that only closes a loop, in m.
const MAX_LOOP_PASS: float = 160.0
## A loop pass is only worth it when the way around is this many times longer than the pass.
const MIN_LOOP_DETOUR: float = 1.8
## How often placing the areas looks for a free spot, per area.
const PLACEMENT_TRIES: int = 400
## Smallest area that can hold a plateau, in m (radius).
const MIN_PLATEAU_RADIUS: float = 28.0
## Largest ore pocket, in m (radius): a dead end, smaller than a basin.
const MAX_POCKET_RADIUS: float = 20.0
## A plateau's mesa: its height, its radius and how far it stands from the area's center (both
## relative to the area's radius); a ramp leads up its side.
const MESA_HEIGHT: float = 4.5
const MESA_RADIUS: float = 0.28
const MESA_OFFSET: float = 0.35
const RAMP_SLOPE: float = 0.45
const RAMP_WIDTH: float = 6.0


## Open ground: a round area (its outline wobbles when carved).
class Area:
	var center: Vector2
	var radius: float
	var kind: LocationLayout.Kind = LocationLayout.Kind.BASIN
	## Walking distance from the landing yard along the passes, in m.
	var distance: float = INF
	## The passes that end here (indices into `LocationLayout.passes`).
	var passes: PackedInt32Array = []
	## A plateau's mesa (x, z, radius) and its ramp: where it starts at the mesa's foot, the way
	## up (towards the mesa) and its length.
	var mesa: Vector3 = Vector3.ZERO
	var ramp_start: Vector2 = Vector2.ZERO
	var ramp_direction: Vector2 = Vector2.ZERO
	var ramp_length: float = 0.0

	func _init(p_center: Vector2, p_radius: float) -> void:
		center = p_center
		radius = p_radius


## A winding way between two areas.
class Pass:
	var from: int
	var to: int
	var width: float
	## From `from`'s center to `to`'s, `LocationLayout.PASS_STEP` apart.
	var points: PackedVector2Array

	func length() -> float:
		var total: float = 0.0
		for i: int in range(1, points.size()):
			total += points[i - 1].distance_to(points[i])
		return total


var areas: Array[Area] = []
var passes: Array[Pass] = []


## A new layout with about `count` areas (fewer when they don't fit). `landing`: the landing yard
## (x, z, radius); `keep_clear`: ground no other area may cover (the ship's landing site).
static func generate(
	rng: RandomNumberGenerator,
	count: int,
	biome: LocationBiome,
	landing: Vector3,
	keep_clear: Rect2
) -> LocationLayout:
	var layout := LocationLayout.new()
	layout._place_areas(rng, maxi(count, 2), biome, landing, keep_clear)
	layout._connect(rng, biome)
	layout._measure()
	layout._assign_kinds(rng)
	return layout


## Area indices that every way from the landing yard to some other area goes through (cutting one
## off splits the layout).
func cut_areas() -> PackedInt32Array:
	var cut := PackedInt32Array()
	for i: int in range(1, areas.size()):
		if _reached_without(i) < areas.size() - 1:
			cut.append(i)
	return cut


## The farthest walking distance from the landing yard to an area, in m.
func farthest() -> float:
	var most: float = 0.0
	for area: Area in areas:
		if is_finite(area.distance):
			most = maxf(most, area.distance)
	return most


## How many passes have to go so the rest is a tree: the number of loops.
func loops() -> int:
	return passes.size() - (areas.size() - 1)


## Areas (Poisson-disk style) around the landing yard: in a square that grows with their number,
## which lies around the yard with a random offset (the ship isn't always in the middle).
func _place_areas(
	rng: RandomNumberGenerator,
	count: int,
	biome: LocationBiome,
	landing: Vector3,
	keep_clear: Rect2
) -> void:
	areas.append(Area.new(Vector2(landing.x, landing.y), landing.z))
	var side: float = biome.area_spread * sqrt(float(count))
	var center := (
		Vector2(landing.x, landing.y)
		+ Vector2(rng.randf_range(-0.3, 0.3) * side, rng.randf_range(-0.3, 0.3) * side)
	)
	var square := Rect2(center - Vector2.ONE * side * 0.5, Vector2.ONE * side)
	for attempt: int in count * PLACEMENT_TRIES:
		if areas.size() >= count:
			break
		var radius: float = rng.randf_range(biome.area_radius.x, biome.area_radius.y)
		var at := Vector2(
			rng.randf_range(square.position.x, square.end.x),
			rng.randf_range(square.position.y, square.end.y)
		)
		if keep_clear.grow(radius + biome.area_spacing).has_point(at):
			continue
		var free: bool = true
		for area: Area in areas:
			if at.distance_to(area.center) < area.radius + radius + biome.area_spacing:
				free = false
				break
		if free:
			areas.append(Area.new(at, radius))


## A tree of the shortest passes (so every area can be reached), then a few loops where the way
## around is long.
func _connect(rng: RandomNumberGenerator, biome: LocationBiome) -> void:
	var joined: Array[bool] = []
	joined.resize(areas.size())
	joined.fill(false)
	joined[0] = true
	for step: int in areas.size() - 1:
		var best: Vector2i = Vector2i(-1, -1)
		var shortest: float = INF
		for a: int in areas.size():
			if not joined[a]:
				continue
			for b: int in areas.size():
				if joined[b]:
					continue
				var gap: float = areas[a].center.distance_to(areas[b].center)
				if gap < shortest:
					shortest = gap
					best = Vector2i(a, b)
		joined[best.y] = true
		_add_pass(rng, biome, best.x, best.y, true)

	var wanted: int = roundi(areas.size() * biome.loops_per_area)
	var kept: Array[int] = _kept_dead_ends()
	_add_loops(rng, biome, wanted, kept, MIN_LOOP_DETOUR, MAX_LOOP_PASS)
	# Where none of those fit, shorter detours and longer passes still make a loop.
	_add_loops(rng, biome, wanted, kept, MIN_LOOP_DETOUR * 0.7, MAX_LOOP_PASS * 1.5)


## Adds loop passes until there are `wanted` loops: between areas (not the `kept` dead ends) at
## most `longest` m apart whose way around is at least `detour` times longer, the longest detours
## first.
func _add_loops(
	rng: RandomNumberGenerator,
	biome: LocationBiome,
	wanted: int,
	kept: Array[int],
	detour: float,
	longest: float
) -> void:
	var candidates: Array[Vector3] = []
	for a: int in areas.size():
		for b: int in range(a + 1, areas.size()):
			if a in kept or b in kept:
				continue
			var gap: float = areas[a].center.distance_to(areas[b].center)
			if gap > longest or _joined(a, b):
				continue
			var around: float = _walk(a)[b]
			if around >= gap * detour:
				candidates.append(Vector3(a, b, around / gap))
	candidates.sort_custom(func(x: Vector3, y: Vector3) -> bool: return x.z > y.z)
	for candidate: Vector3 in candidates:
		if loops() >= wanted:
			break
		var a: int = int(candidate.x)
		var b: int = int(candidate.y)
		# Earlier loops may have made this one short.
		if _walk(a)[b] < areas[a].center.distance_to(areas[b].center) * detour:
			continue
		_add_pass(rng, biome, a, b, false)


## The farthest dead ends of the tree, kept as dead ends (no loop reaches them): they become the
## ore pockets and nest hollows.
func _kept_dead_ends() -> Array[int]:
	var distances: PackedFloat32Array = _walk(0)
	var dead_ends: Array[int] = []
	for i: int in range(1, areas.size()):
		if areas[i].passes.size() == 1:
			dead_ends.append(i)
	dead_ends.sort_custom(func(x: int, y: int) -> bool: return distances[x] > distances[y])
	return dead_ends.slice(0, _pocket_count() + _hollow_count())


## How many ore pockets and nest hollows a layout has: about one each per eight areas.
func _pocket_count() -> int:
	return maxi(1, roundi(areas.size() / 8.0))


func _hollow_count() -> int:
	return maxi(1, roundi(areas.size() / 8.0))


## Adds a pass from area `a` to `b`, bent to one side unless that makes it cross another pass or
## run through another area. A pass the tree needs is added straight if bending doesn't fit; a
## loop pass is left out.
func _add_pass(
	rng: RandomNumberGenerator, biome: LocationBiome, a: int, b: int, needed: bool
) -> void:
	var bend: float = rng.randf_range(-MAX_BEND, MAX_BEND)
	var width: float = rng.randf_range(biome.pass_width.x, biome.pass_width.y)
	var points: PackedVector2Array = _curve(areas[a].center, areas[b].center, bend)
	if not _fits(points, a, b, width):
		points = _curve(areas[a].center, areas[b].center, 0.0)
		if not needed and not _fits(points, a, b, width):
			return
	var added := Pass.new()
	added.from = a
	added.to = b
	added.width = width
	added.points = points
	areas[a].passes.append(passes.size())
	areas[b].passes.append(passes.size())
	passes.append(added)


## A quadratic curve from `from` to `to`, its middle pushed sideways by `bend` times its length.
static func _curve(from: Vector2, to: Vector2, bend: float) -> PackedVector2Array:
	var length: float = from.distance_to(to)
	var side: Vector2 = (to - from).normalized().orthogonal()
	var middle: Vector2 = (from + to) * 0.5 + side * bend * length
	var steps: int = maxi(2, ceili(length * (1.0 + absf(bend)) / PASS_STEP))
	var points := PackedVector2Array()
	for i: int in steps + 1:
		var t: float = float(i) / steps
		points.append(from.lerp(middle, t).lerp(middle.lerp(to, t), t))
	return points


## Whether a pass along `points` from area `a` to `b` stays clear of the other passes and areas.
func _fits(points: PackedVector2Array, a: int, b: int, width: float) -> bool:
	for k: int in areas.size():
		if k == a or k == b:
			continue
		var keep: float = areas[k].radius + width * 0.5
		for point: Vector2 in points:
			if point.distance_to(areas[k].center) < keep:
				return false
	for other: Pass in passes:
		var shared: Array[int] = [other.from, other.to]
		if a in shared or b in shared:
			continue
		if _polylines_cross(points, other.points):
			return false
	return true


static func _polylines_cross(first: PackedVector2Array, second: PackedVector2Array) -> bool:
	for i: int in range(1, first.size()):
		for j: int in range(1, second.size()):
			if (
				Geometry2D.segment_intersects_segment(
					first[i - 1], first[i], second[j - 1], second[j]
				)
				!= null
			):
				return true
	return false


func _joined(a: int, b: int) -> bool:
	for index: int in areas[a].passes:
		var other: Pass = passes[index]
		if other.from == b or other.to == b:
			return true
	return false


## Walking distance from area `from` to every area along the passes (INF where there's no way).
func _walk(from: int, skip: int = -1) -> PackedFloat32Array:
	var best := PackedFloat32Array()
	best.resize(areas.size())
	best.fill(INF)
	best[from] = 0.0
	var done: Array[bool] = []
	done.resize(areas.size())
	done.fill(false)
	for step: int in areas.size():
		var current: int = -1
		for k: int in areas.size():
			if not done[k] and k != skip and (current < 0 or best[k] < best[current]):
				current = k
		if current < 0 or not is_finite(best[current]):
			break
		done[current] = true
		for index: int in areas[current].passes:
			var way: Pass = passes[index]
			var next: int = way.to if way.from == current else way.from
			if next == skip:
				continue
			best[next] = minf(best[next], best[current] + way.length())
	return best


func _reached_without(skip: int) -> int:
	var reached: int = 0
	for distance: float in _walk(0, skip):
		if is_finite(distance):
			reached += 1
	return reached


func _measure() -> void:
	var distances: PackedFloat32Array = _walk(0)
	for i: int in areas.size():
		areas[i].distance = distances[i]


## What each area is, by where it lies in the graph: the farthest dead ends hold the rich ore, the
## next ones are nest hollows, areas where three or more passes meet are crossroads; plateaus and
## craters stand out in the far half. Their numbers grow with the layout (about one each per eight
## or ten areas).
func _assign_kinds(rng: RandomNumberGenerator) -> void:
	areas[0].kind = Kind.LANDING
	var by_distance: Array[int] = []
	for i: int in range(1, areas.size()):
		by_distance.append(i)
	by_distance.sort_custom(
		func(x: int, y: int) -> bool: return areas[x].distance < areas[y].distance
	)
	var dead_ends: Array[int] = []
	for i: int in by_distance:
		if areas[i].passes.size() == 1:
			dead_ends.append(i)
	var pockets: int = _pocket_count()
	var hollows: int = _hollow_count()
	while pockets > 0 and not dead_ends.is_empty():
		var pocket: int = dead_ends.pop_back()
		areas[pocket].kind = Kind.ORE_POCKET
		pockets -= 1
	while hollows > 0 and not dead_ends.is_empty():
		var hollow: int = dead_ends.pop_back()
		areas[hollow].kind = Kind.NEST_HOLLOW
		hollows -= 1
	for i: int in by_distance:
		if areas[i].kind == Kind.BASIN and areas[i].passes.size() >= 3:
			areas[i].kind = Kind.CROSSROADS
	var far_half: Array[int] = []
	for k: int in range(floori(by_distance.size() / 2.0), by_distance.size()):
		if areas[by_distance[k]].kind == Kind.BASIN:
			far_half.append(by_distance[k])
	# Shuffled with the layout's own generator, so the same seed gives the same layout.
	for i: int in range(far_half.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = far_half[i]
		far_half[i] = far_half[j]
		far_half[j] = swap
	var plateaus: int = roundi(areas.size() / 10.0)
	var craters: int = roundi(areas.size() / 10.0)
	for i: int in far_half:
		if plateaus > 0 and areas[i].radius >= MIN_PLATEAU_RADIUS:
			areas[i].kind = Kind.PLATEAU
			_shape_plateau(areas[i])
			plateaus -= 1
		elif craters > 0:
			areas[i].kind = Kind.CRATER
			craters -= 1
	for i: int in by_distance:
		if areas[i].kind == Kind.ORE_POCKET:
			areas[i].radius = minf(areas[i].radius, MAX_POCKET_RADIUS)


## Puts the plateau's mesa where no pass comes in (in the widest gap between them), with its ramp
## leading up along its side.
func _shape_plateau(area: Area) -> void:
	var angles: Array[float] = []
	for index: int in area.passes:
		var way: Pass = passes[index]
		var toward: Vector2 = (
			way.points[1] if way.from == areas.find(area) else way.points[way.points.size() - 2]
		)
		angles.append((toward - area.center).angle())
	angles.sort()
	var widest: float = TAU
	var facing: float = 0.0
	if not angles.is_empty():
		widest = 0.0
		for i: int in angles.size():
			var next: float = (
				angles[(i + 1) % angles.size()] + (TAU if i == angles.size() - 1 else 0.0)
			)
			if next - angles[i] > widest:
				widest = next - angles[i]
				facing = angles[i] + widest * 0.5
	var out := Vector2.from_angle(facing)
	var mesa_radius: float = area.radius * MESA_RADIUS
	var mesa_center: Vector2 = area.center + out * area.radius * MESA_OFFSET
	area.mesa = Vector3(mesa_center.x, mesa_center.y, mesa_radius)
	# Straight up to the mesa's flank, beside it (not towards the area's center, where the passes
	# meet).
	area.ramp_length = MESA_HEIGHT / RAMP_SLOPE
	var side: Vector2 = out.orthogonal()
	area.ramp_direction = -side
	area.ramp_start = mesa_center + side * (mesa_radius + area.ramp_length)
