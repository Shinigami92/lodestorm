class_name LocationLayout
extends RefCounted
## The plan of a generated location as a graph: open areas (basins, crossroads, dead ends with rich
## ore, nest hollows, plateaus, craters, and the biome's own kinds) joined by passes (winding ways
## or short bridges, by the biome), with the biome's barrier everywhere else. The first area is the
## landing yard in front of the ship's ramp. Every visit lays out a new graph from the seed;
## `GeneratedLocation` carves it into the ground. The passes form a tree plus a few loops, and never
## cross each other. Plain data, so it can be made on a worker thread. All values are greybox, TBD
## (playtest).

enum Kind {
	LANDING,
	BASIN,
	CROSSROADS,
	ORE_POCKET,
	NEST_HOLLOW,
	PLATEAU,
	CRATER,
	## Frost fields: a huge flat area with cracks running in from its edge.
	ICE_SHELF,
	## Frost fields: an area with a round, flat lake of slick ice beside the ways through it.
	FROZEN_LAKE,
	## Salt pans: an area dotted with round pits, a maze in the open.
	SINKHOLE_FIELD,
	## Salt pans: one of the biggest areas, flat and empty.
	BRINE_FLAT,
	## Ash fields: an ore pocket with lava all around, reached by its one crossing.
	LAVA_ISLAND,
	## Ash fields: an area with vents (the biome's hazard).
	VENT_FIELD,
	## Dust flats: an area with rock pillars (buttes) standing in the open, cover.
	BUTTE_FIELD,
	## Dust flats: a long area with a dry, sandy riverbed winding along it.
	DRY_WASH,
	## Glass plains: an area climbing over two slabs by ramps, at the back of it.
	TERRACE_STAIRS,
	## Glass plains: an area with glass spike clusters (cover) and shards on the ground (the
	## biome's hazard).
	SHARD_GARDEN,
	## Overgrowth: an area with shallow mud pools (the biome's hazard).
	MIRE,
	## Overgrowth: an area with giant fungal stalks standing in it (cover, short sightlines).
	FUNGAL_GROVE,
}

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
## Smallest area that can hold a frozen lake, in m (radius); the lake's radius and how far it lies
## from the area's center, relative to the area's radius (the location shrinks it to keep it off
## the lanes).
const MIN_LAKE_AREA_RADIUS: float = 22.0
const LAKE_RADIUS: float = 0.6
const LAKE_OFFSET: float = 0.25
## An ice shelf's cracks: at most this many, each in a gap of at least `CRACK_GAP` between the
## passes coming in, from beyond its edge to this far from its center (relative to its radius).
const MAX_CRACKS: int = 3
const CRACK_GAP: float = deg_to_rad(70.0)
const CRACK_OUTER: float = 1.35
const CRACK_INNER: float = 0.35
## How far a crack's points stray sideways, in m.
const CRACK_JAG: float = 1.5
## A sinkhole field's pits: their radius (smallest, largest), the walkable ground kept between
## them and around the area's middle, in m, and how far out they lie (relative to the area's
## radius, the pit's edge inside it).
const PIT_RADIUS: Vector2 = Vector2(3.0, 5.5)
const PIT_SPACING: float = 7.0
const PIT_MIDDLE: float = 5.0
const PIT_REACH: float = 0.75
## Pits a sinkhole field tries to fit, per m of its radius (the location drops the ones on lanes).
const PITS_PER_RADIUS: float = 0.3
## Shortest crossing to a lava island, in m (between the outlines, before they wobble).
const MIN_ISLAND_BRIDGE: float = 16.0
## Smallest area that holds a vent field, in m (radius).
const MIN_VENT_FIELD_RADIUS: float = 20.0
## A butte field's buttes: their radius (smallest, largest), the walkable ground kept between them
## and around the area's middle, in m, how far out they lie (relative to the area's radius, the
## butte's edge inside it), how many (fewest, most) and the smallest area that holds them.
const BUTTE_RADIUS: Vector2 = Vector2(3.0, 6.0)
const BUTTE_SPACING: float = 8.0
const BUTTE_MIDDLE: float = 6.0
const BUTTE_REACH: float = 0.7
const BUTTES: Vector2i = Vector2i(2, 4)
const MIN_BUTTE_FIELD_RADIUS: float = 22.0
## A dry wash: how wide it is, relative to its length (its radius is half the length), and the
## smallest area that holds one, in m (radius). Its bed winds along it.
const WASH_WIDTH: float = 0.55
const MIN_WASH_RADIUS: float = 26.0
## How far the bed strays sideways, relative to the wash's half width, and how many half waves it
## makes along the wash.
const BED_MEANDER: float = 0.45
const BED_WAVES: float = 3.0
## Terrace stairs: two square slabs at the back of the area (where no pass comes in), the lower one
## a step above the area, the upper one on it; their half sides and how far out the lower one
## stands (relative to the area's radius), the smallest area and the widest gap between its passes
## it needs.
const STAIRS_LOWER: float = 0.3
const STAIRS_UPPER: float = 0.16
const STAIRS_OFFSET: float = 0.5
const MIN_STAIRS_RADIUS: float = 28.0
const STAIRS_GAP: float = deg_to_rad(160.0)
## Smallest area that holds a shard garden, in m (radius).
const MIN_GARDEN_RADIUS: float = 20.0
## A mire's mud pools: their radius (smallest, largest), the walkable ground kept between them and
## around the area's middle, in m, how far out they lie (relative to the area's radius, the pool's
## edge inside it), how many (fewest, most; off the passes' lanes) and the smallest area that holds
## them.
const POOL_RADIUS: Vector2 = Vector2(3.5, 7.0)
const POOL_SPACING: float = 4.0
const POOL_MIDDLE: float = 4.0
const POOL_REACH: float = 0.85
const POOLS: Vector2i = Vector2i(3, 5)
const MIN_MIRE_RADIUS: float = 24.0
## Room between a pool and a lane, in m (the location drops pools closer than its own clearance).
const POOL_LANE_CLEARANCE: float = 3.0
## Smallest area that holds a fungal grove, in m (radius).
const MIN_GROVE_RADIUS: float = 20.0
## The levels of terraces (`LocationBiome.terrace_step`), in steps from the landing yard's
## (lowest, highest).
const LEVELS: Vector2i = Vector2i(-1, 2)


## A slab of terrace stairs: a square at `steps` steps above its area, its sides along the area's
## `facing`, and the ramp up to it.
class Slab:
	var center: Vector2
	var half: float
	var steps: int
	## Where the ramp starts (at the ground below), the way up and its length.
	var ramp_start: Vector2
	var ramp_direction: Vector2
	var ramp_length: float


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
	## A frozen lake's lake (x, z, radius).
	var lake: Vector3 = Vector3.ZERO
	## An ice shelf's cracks: from beyond its edge inwards, `LocationLayout.PASS_STEP` apart.
	var cracks: Array[PackedVector2Array] = []
	## A sinkhole field's pits (x, z, radius).
	var pits: Array[Vector3] = []
	## A butte field's buttes (x, z, radius).
	var buttes: Array[Vector3] = []
	## A mire's mud pools (x, z, radius).
	var pools: Array[Vector3] = []
	## The way a dry wash runs along (its length), or terrace stairs climb (out from the middle).
	var facing: Vector2 = Vector2.ZERO
	## A dry wash's bed: points along its middle, `LocationLayout.PASS_STEP` apart.
	var bed: PackedVector2Array = []
	## Terrace stairs' slabs, the lower one first.
	var slabs: Array[LocationLayout.Slab] = []
	## The height of its slab (`LocationBiome.terrace_step`), in m.
	var level: float = 0.0

	func _init(p_center: Vector2, p_radius: float) -> void:
		center = p_center
		radius = p_radius

	## Whether it holds the rarest ore: an ore pocket (a lava island is one too).
	func holds_rich_ore() -> bool:
		return kind in [LocationLayout.Kind.ORE_POCKET, LocationLayout.Kind.LAVA_ISLAND]


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
	layout._assign_kinds(rng, biome)
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
	var bridges: bool = biome.pass_style == LocationBiome.PassStyle.BRIDGES
	for attempt: int in count * PLACEMENT_TRIES:
		if areas.size() >= count:
			break
		var radius: float = rng.randf_range(biome.area_radius.x, biome.area_radius.y)
		var at := Vector2(
			rng.randf_range(square.position.x, square.end.x),
			rng.randf_range(square.position.y, square.end.y)
		)
		if bridges:
			# Next to an area already there, a bridge's length away.
			var beside: Area = areas[rng.randi() % areas.size()]
			var gap: float = rng.randf_range(biome.area_spacing, biome.longest_bridge)
			at = (
				beside.center
				+ Vector2.from_angle(rng.randf() * TAU) * (beside.radius + radius + gap)
			)
			if not square.has_point(at):
				continue
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
				var gap: float = _span(biome, a, b)
				if gap < shortest:
					shortest = gap
					best = Vector2i(a, b)
		joined[best.y] = true
		_add_pass(rng, biome, best.x, best.y, true)
	if biome.terrace_step > 0.0:
		_assign_levels(rng, biome)

	var wanted: int = roundi(areas.size() * biome.loops_per_area)
	var kept: Array[int] = _kept_dead_ends()
	var longest: Vector2 = Vector2(MAX_LOOP_PASS, MAX_LOOP_PASS * 1.5)
	if biome.pass_style == LocationBiome.PassStyle.BRIDGES:
		longest = Vector2(1.0, 1.4) * biome.longest_bridge
	_add_loops(rng, biome, wanted, kept, MIN_LOOP_DETOUR, longest.x)
	# Where none of those fit, shorter detours and longer passes still make a loop.
	_add_loops(rng, biome, wanted, kept, MIN_LOOP_DETOUR * 0.7, longest.y)


## How far a pass from area `a` to `b` reaches, for the tree and the loops, in m: from center to
## center, or for bridges from edge to edge (what the bridge crosses).
func _span(biome: LocationBiome, a: int, b: int) -> float:
	var span: float = areas[a].center.distance_to(areas[b].center)
	if biome.pass_style == LocationBiome.PassStyle.BRIDGES:
		span -= areas[a].radius + areas[b].radius
	return span


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
			# A ramp climbs one step at most, and never down from the landing yard.
			if absf(areas[a].level - areas[b].level) > biome.terrace_step + 0.01:
				continue
			if a == 0 and areas[b].level < 0.0:
				continue
			var gap: float = areas[a].center.distance_to(areas[b].center)
			if _span(biome, a, b) > longest or _joined(a, b):
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
	if biome.pass_style == LocationBiome.PassStyle.BRIDGES:
		bend = 0.0
	var width: float = rng.randf_range(biome.pass_width.x, biome.pass_width.y)
	var points: PackedVector2Array = _curve(areas[a].center, areas[b].center, bend)
	if biome.pass_style in [LocationBiome.PassStyle.SLOT_CANYONS, LocationBiome.PassStyle.TRAILS]:
		points = _wind(areas[a].center, areas[b].center, bend)
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


## An S-shaped curve from `from` to `to` (a slot canyon, a trail): it bends to one side, then the
## other, by `bend` (relative to its length) at most.
static func _wind(from: Vector2, to: Vector2, bend: float) -> PackedVector2Array:
	var length: float = from.distance_to(to)
	var along: Vector2 = to - from
	# A cubic curve strays about 0.29 times as far as its control points stand off the line.
	var off: Vector2 = along.normalized().orthogonal() * bend * length / 0.29
	var first: Vector2 = from + along / 3.0 + off
	var second: Vector2 = from + along * 2.0 / 3.0 - off
	var steps: int = maxi(2, ceili(length * (1.0 + absf(bend) * 2.0) / PASS_STEP))
	var points := PackedVector2Array()
	for i: int in steps + 1:
		var t: float = float(i) / steps
		var s: float = 1.0 - t
		points.append(
			from * s * s * s + first * 3.0 * s * s * t + second * 3.0 * s * t * t + to * t * t * t
		)
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


## Gives every area its level (terraces), along the tree's passes from the landing yard (level 0):
## each a step below, at or above the one its pass comes from, within `LEVELS`; never below the
## landing yard next to it (the landing site's flat ground would cut the ramp's top off).
func _assign_levels(rng: RandomNumberGenerator, biome: LocationBiome) -> void:
	var steps: PackedInt32Array = []
	steps.resize(areas.size())
	var reached: Array[bool] = []
	reached.resize(areas.size())
	reached.fill(false)
	reached[0] = true
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for index: int in areas[current].passes:
			var way: Pass = passes[index]
			var next: int = way.to if way.from == current else way.from
			if reached[next]:
				continue
			reached[next] = true
			var lowest: int = 0 if current == 0 else LEVELS.x
			steps[next] = clampi(steps[current] + rng.randi_range(-1, 1), lowest, LEVELS.y)
			areas[next].level = steps[next] * biome.terrace_step
			queue.append(next)


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
## next ones are nest hollows, areas where three or more passes meet are crossroads; the biome's
## own kinds come next, then plateaus and craters stand out in the far half. Their numbers grow
## with the layout (about one each per eight or ten areas).
func _assign_kinds(rng: RandomNumberGenerator, biome: LocationBiome) -> void:
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
	for kind: Kind in biome.area_kinds:
		var count: int = maxi(1, roundi(areas.size() * biome.area_kinds_per_area))
		_assign_own_kind(rng, biome, kind, count)
	if Kind.LAVA_ISLAND in biome.area_kinds:
		for area: Area in areas:
			if area.kind == Kind.ORE_POCKET:
				area.kind = Kind.LAVA_ISLAND
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
		if areas[i].holds_rich_ore():
			_shrink_pocket(biome, i)


## Shrinks the ore pocket `index` to `MAX_POCKET_RADIUS`; with bridges it moves towards the area
## its pass comes from by as much, so the bridge stays as short (inside its old outline, so it keeps
## clear of the others). A lava island keeps a crossing of at least `MIN_ISLAND_BRIDGE` instead.
func _shrink_pocket(biome: LocationBiome, index: int) -> void:
	var pocket: Area = areas[index]
	var shrink: float = maxf(pocket.radius - MAX_POCKET_RADIUS, 0.0)
	pocket.radius -= shrink
	if biome.pass_style != LocationBiome.PassStyle.BRIDGES:
		return
	for pass_index: int in pocket.passes:
		var way: Pass = passes[pass_index]
		var other: Area = areas[way.to if way.from == index else way.from]
		var gap: float = pocket.center.distance_to(other.center) - pocket.radius - other.radius
		var toward: float = shrink
		if pocket.kind == Kind.LAVA_ISLAND:
			toward = minf(gap - MIN_ISLAND_BRIDGE, shrink)
		# An island too close moves away, where there's room.
		var moved: Vector2 = pocket.center.move_toward(other.center, toward)
		if toward > 0.0 or (toward < 0.0 and _has_room(biome, index, moved)):
			pocket.center = moved
		way.points = _curve(areas[way.from].center, areas[way.to].center, 0.0)


## Whether area `index` keeps clear of the others at `at` (by `LocationBiome.area_spacing`).
func _has_room(biome: LocationBiome, index: int, at: Vector2) -> bool:
	for k: int in areas.size():
		var spacing: float = areas[k].radius + areas[index].radius + biome.area_spacing
		if k != index and at.distance_to(areas[k].center) < spacing:
			return false
	return true


## Gives `count` of the basins the biome's own `kind`: ice shelves, brine flats and dry washes the
## biggest ones, the others any big enough (lava islands are the ore pockets, see `_assign_kinds`).
## With too few basins (many loops make crossroads of most areas), crossroads too, the ones with the
## fewest passes first.
func _assign_own_kind(
	rng: RandomNumberGenerator, biome: LocationBiome, kind: Kind, count: int
) -> void:
	if kind == Kind.LAVA_ISLAND:
		return
	var basins: Array[int] = []
	for i: int in areas.size():
		if areas[i].kind == Kind.BASIN:
			basins.append(i)
	for i: int in range(basins.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = basins[i]
		basins[i] = basins[j]
		basins[j] = swap
	if kind in [Kind.ICE_SHELF, Kind.BRINE_FLAT, Kind.DRY_WASH]:
		basins.sort_custom(func(x: int, y: int) -> bool: return areas[x].radius > areas[y].radius)
	var crossroads: Array[int] = []
	for i: int in areas.size():
		if areas[i].kind == Kind.CROSSROADS:
			crossroads.append(i)
	# The fewest passes first: their lanes leave the most room.
	crossroads.sort_custom(
		func(x: int, y: int) -> bool: return areas[x].passes.size() < areas[y].passes.size()
	)
	basins.append_array(crossroads)
	for i: int in basins:
		if count <= 0:
			break
		var area: Area = areas[i]
		match kind:
			Kind.FROZEN_LAKE:
				if area.radius < MIN_LAKE_AREA_RADIUS:
					continue
				_shape_lake(area)
			Kind.ICE_SHELF:
				_shape_shelf(rng, area)
			Kind.SINKHOLE_FIELD:
				_shape_pits(rng, area)
				if area.pits.is_empty():
					continue
			Kind.VENT_FIELD:
				if area.radius < MIN_VENT_FIELD_RADIUS:
					continue
			Kind.SHARD_GARDEN:
				if area.radius < MIN_GARDEN_RADIUS:
					continue
			Kind.FUNGAL_GROVE:
				if area.radius < MIN_GROVE_RADIUS:
					continue
			Kind.MIRE:
				if area.radius < MIN_MIRE_RADIUS:
					continue
				area.pools = _spread_circles(
					rng,
					area,
					POOL_RADIUS,
					POOL_SPACING,
					POOL_MIDDLE,
					POOL_REACH,
					POOLS.y,
					func(at: Vector2, radius: float) -> bool: return _fits_pool(area, at, radius)
				)
				if area.pools.size() < POOLS.x:
					area.pools.clear()
					continue
			Kind.BUTTE_FIELD:
				if area.radius < MIN_BUTTE_FIELD_RADIUS:
					continue
				var wanted: int = rng.randi_range(BUTTES.x, BUTTES.y)
				area.buttes = _spread_circles(
					rng, area, BUTTE_RADIUS, BUTTE_SPACING, BUTTE_MIDDLE, BUTTE_REACH, wanted
				)
				if area.buttes.size() < BUTTES.x:
					area.buttes.clear()
					continue
			Kind.DRY_WASH:
				if area.radius < MIN_WASH_RADIUS:
					continue
				_shape_wash(rng, area)
			Kind.TERRACE_STAIRS:
				if area.radius < MIN_STAIRS_RADIUS or _widest_gap(area).y < STAIRS_GAP:
					continue
				_shape_stairs(biome, area)
		area.kind = kind
		count -= 1


## The directions the passes come into `area` from, as angles, sorted.
func _pass_angles(area: Area) -> Array[float]:
	var angles: Array[float] = []
	for index: int in area.passes:
		var way: Pass = passes[index]
		var toward: Vector2 = (
			way.points[1] if way.from == areas.find(area) else way.points[way.points.size() - 2]
		)
		angles.append((toward - area.center).angle())
	angles.sort()
	return angles


## The direction (an angle) in the middle of the widest gap between the passes coming into `area`,
## and how wide that gap is (an angle).
func _widest_gap(area: Area) -> Vector2:
	var angles: Array[float] = _pass_angles(area)
	var widest: float = 0.0
	var facing: float = 0.0
	for i: int in angles.size():
		var next: float = angles[(i + 1) % angles.size()] + (TAU if i == angles.size() - 1 else 0.0)
		if next - angles[i] > widest:
			widest = next - angles[i]
			facing = angles[i] + widest * 0.5
	return Vector2(facing, widest)


## Puts the frozen lake where no pass comes in (in the widest gap between them).
func _shape_lake(area: Area) -> void:
	var at: Vector2 = (
		area.center + Vector2.from_angle(_widest_gap(area).x) * area.radius * LAKE_OFFSET
	)
	area.lake = Vector3(at.x, at.y, area.radius * LAKE_RADIUS)


## Runs jagged cracks into the ice shelf from beyond its edge, each in the middle of a wide gap
## between the passes coming in.
func _shape_shelf(rng: RandomNumberGenerator, area: Area) -> void:
	var angles: Array[float] = _pass_angles(area)
	var directions: Array[float] = []
	if angles.size() <= 1:
		var away: float = angles[0] + PI if angles.size() == 1 else rng.randf() * TAU
		directions = [away - 1.2, away + 1.2]
	else:
		for i: int in angles.size():
			var next: float = (
				angles[(i + 1) % angles.size()] + (TAU if i == angles.size() - 1 else 0.0)
			)
			if next - angles[i] >= CRACK_GAP:
				directions.append((angles[i] + next) * 0.5)
	area.cracks.clear()
	for direction: float in directions.slice(0, MAX_CRACKS):
		var out := Vector2.from_angle(direction)
		var side: Vector2 = out.orthogonal()
		var length: float = area.radius * (CRACK_OUTER - CRACK_INNER)
		var steps: int = maxi(2, ceili(length / PASS_STEP))
		var crack := PackedVector2Array()
		var stray: float = 0.0
		for i: int in steps + 1:
			var along: float = area.radius * CRACK_OUTER - length * i / steps
			stray = clampf(stray + rng.randf_range(-0.5, 0.5), -CRACK_JAG, CRACK_JAG)
			crack.append(area.center + out * along + side * stray)
		area.cracks.append(crack)


## Dots the sinkhole field with round pits, apart from each other and off its middle (where the
## ways through it meet).
func _shape_pits(rng: RandomNumberGenerator, area: Area) -> void:
	var wanted: int = roundi(area.radius * PITS_PER_RADIUS)
	area.pits = _spread_circles(rng, area, PIT_RADIUS, PIT_SPACING, PIT_MIDDLE, PIT_REACH, wanted)


## Up to `wanted` circles (x, z, radius) in `area`: their radius between `radii`, at least
## `spacing` m apart and `middle` m off its middle, inside `reach` times its radius, where `fits`
## (at, radius) agrees, if given.
static func _spread_circles(
	rng: RandomNumberGenerator,
	area: Area,
	radii: Vector2,
	spacing: float,
	middle: float,
	reach: float,
	wanted: int,
	fits: Callable = Callable()
) -> Array[Vector3]:
	var circles: Array[Vector3] = []
	for attempt: int in wanted * 20:
		if circles.size() >= wanted:
			break
		var radius: float = rng.randf_range(radii.x, radii.y)
		var outer: float = area.radius * reach - radius
		var low: float = radius + middle
		if outer <= low:
			continue
		var at: Vector2 = (
			area.center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(low, outer)
		)
		var free: bool = true
		for circle: Vector3 in circles:
			if at.distance_to(Vector2(circle.x, circle.y)) < circle.z + radius + spacing:
				free = false
				break
		if free and (not fits.is_valid() or fits.call(at, radius)):
			circles.append(Vector3(at.x, at.y, radius))
	return circles


## Whether a mud pool of `radius` at `at` fits in `area`: with its shore inside the area's outline
## however it wobbles, off the lanes of the passes coming in (see `LocationPasses`; they end in the
## area's middle).
func _fits_pool(area: Area, at: Vector2, radius: float) -> bool:
	var innermost: float = area.radius * (1.0 - GeneratedLocation.AREA_WOBBLE)
	if at.distance_to(area.center) + radius + LocationFeatures.POOL_SHORE > innermost:
		return false
	var keep: float = radius + LocationPasses.LANE_HALF_WIDTH + POOL_LANE_CLEARANCE
	for index: int in area.passes:
		for point: Vector2 in passes[index].points:
			var inside: float = point.distance_to(area.center)
			if (
				inside >= area.radius * LocationPasses.LANE_FREE_MIDDLE
				and point.distance_to(at) < keep
			):
				return false
	return true


## Lays the dry wash along the passes coming in (so they meet its ends) and winds its bed along it.
func _shape_wash(rng: RandomNumberGenerator, area: Area) -> void:
	# The mean of the passes' directions, each counted both ways (a line, not an arrow).
	var mean := Vector2.ZERO
	for angle: float in _pass_angles(area):
		mean += Vector2.from_angle(angle * 2.0)
	var axis: float = mean.angle() * 0.5 if mean.length() > 0.01 else rng.randf() * TAU
	area.facing = Vector2.from_angle(axis)
	var side: Vector2 = area.facing.orthogonal()
	var phase: float = rng.randf() * TAU
	var stray: float = area.radius * WASH_WIDTH * BED_MEANDER
	area.bed.clear()
	var steps: int = ceili(area.radius * 2.0 / PASS_STEP)
	for i: int in steps + 1:
		var along: float = -area.radius + area.radius * 2.0 * i / steps
		var wave: float = sin(phase + along / area.radius * PI * BED_WAVES * 0.5)
		area.bed.append(area.center + area.facing * along + side * wave * stray)


## Puts the terrace stairs' two slabs at the back of the area (in the widest gap between the passes
## coming in), the upper one on the lower one's far side; the ramp onto the lower slab leads up
## beside it, the one onto the upper slab up across the lower slab's front.
func _shape_stairs(biome: LocationBiome, area: Area) -> void:
	area.facing = Vector2.from_angle(_widest_gap(area).x)
	var side: Vector2 = area.facing.orthogonal()
	var length: float = biome.terrace_step / RAMP_SLOPE
	var lower := Slab.new()
	lower.half = area.radius * STAIRS_LOWER
	lower.center = area.center + area.facing * area.radius * STAIRS_OFFSET
	lower.steps = 1
	lower.ramp_length = length
	lower.ramp_direction = -side
	lower.ramp_start = lower.center + side * (lower.half + length)
	var upper := Slab.new()
	upper.half = area.radius * STAIRS_UPPER
	upper.center = lower.center + area.facing * (lower.half - upper.half)
	upper.steps = 2
	upper.ramp_length = length
	upper.ramp_direction = area.facing
	upper.ramp_start = upper.center - area.facing * (upper.half + length)
	area.slabs = [lower, upper]


## Puts the plateau's mesa where no pass comes in (in the widest gap between them), with its ramp
## leading up along its side.
func _shape_plateau(area: Area) -> void:
	var out := Vector2.from_angle(_widest_gap(area).x)
	var mesa_radius: float = area.radius * MESA_RADIUS
	var mesa_center: Vector2 = area.center + out * area.radius * MESA_OFFSET
	area.mesa = Vector3(mesa_center.x, mesa_center.y, mesa_radius)
	# Straight up to the mesa's flank, beside it (not towards the area's center, where the passes
	# meet).
	area.ramp_length = MESA_HEIGHT / RAMP_SLOPE
	var side: Vector2 = out.orthogonal()
	area.ramp_direction = -side
	area.ramp_start = mesa_center + side * (mesa_radius + area.ramp_length)
