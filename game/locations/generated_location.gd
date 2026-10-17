class_name GeneratedLocation
extends Node3D
## An outside world generated from a seed and a biome when it appears (every run gets a fresh
## one): open areas joined by winding passes (a `LocationLayout`), carved into high rock nobody can
## climb, with plants and rocks, ore fields and alien nests. The ship stands at the location's
## origin, on a flat landing site; the location's axes are the ship's (nose to -x, ramp to +x).
## Ores and nests only lie where players can walk to from the ship; rarer ores lie farther along
## the passes, the rarest in dead ends. Every walkable spot leads back to the ship: there are no
## pits to fall into.
## Everything the generator places is greybox; the values are TBD (playtest).
## Generating takes a while, so it runs in two steps: `plan` does the heavy work without touching
## nodes or servers, so it can run on a worker thread while the location is outside the tree (the
## ship prepares the next location before and during the flight); `build` then adds the nodes. A
## location that enters the tree unbuilt does both right away.

const ORE_NODE: PackedScene = preload("res://game/mining/ore_node.tscn")
const ALIEN_NEST: PackedScene = preload("res://game/aliens/nest/alien_nest.tscn")
## Grid squares per chunk side: the ground and the scatter are cut into chunks so the parts out of
## view are culled.
const CHUNK_CELLS: int = 25
## Steepest slope players and aliens walk up, in rise per m (about 40°).
const MAX_WALK_SLOPE: float = 0.84
## How much the ground under an ore node or nest may rise from its lowest to its highest point
## (relative to the site's radius) before it's flattened.
const MAX_SITE_RISE: float = 0.3
const ORE_SITE_RADIUS: float = 3.0
const NEST_SITE_RADIUS: float = 6.0
## Height of the invisible walls at the edges, in m.
const BOUNDS_HEIGHT: float = 60.0
## How often a placement looks for a fitting spot before giving up.
const PLACEMENT_TRIES: int = 300
## How far (in grid points) the ground is checked for higher ground nearby when painting scree.
const SCREE_REACH: int = 2
## Half the width of the lane along every pass (up to the middle of the areas it joins) that
## blocking plants and rocks, ore nodes and nests keep free, plus the room the widest of them
## needs, in m.
const LANE_HALF_WIDTH: float = 5.0
## How far into an area (relative to its radius) a lane leads; the middle is open enough.
const LANE_FREE_MIDDLE: float = 0.6
## How much an area's or a pass's outline wobbles, relative to its radius or half width.
const AREA_WOBBLE: float = 0.2
const PASS_WOBBLE: float = 0.3
## Open ground around the landing site, in m: more than `landing_falloff`, so the flat site never
## pulls the rock down into a ramp.
const LANDING_MARGIN: float = 10.0
## Distance over which the ground flattened under an ore node or nest blends back, in m.
const SITE_FALLOFF: float = 3.0
## Share of the wall's height the cliff rises on its first grid square: much more than players
## can step up (`MAX_WALK_SLOPE`).
const FIRST_STEP: float = 0.6
## How close a nest may be to the landing site in a straight line, relative to
## `LocationBiome.nest_min_distance` (which counts along the passes).
const NEST_STRAIGHT_SHARE: float = 0.6
## A nest hollow's depth and a crater's (its rim rises around it), in m.
const HOLLOW_DEPTH: float = 2.5
const CRATER_DEPTH: float = 3.0
const CRATER_RIM: float = 2.0
## Kinds of areas whose open ground has its own shape.
const SHAPED_KINDS: Array[LocationLayout.Kind] = [
	LocationLayout.Kind.NEST_HOLLOW, LocationLayout.Kind.CRATER, LocationLayout.Kind.PLATEAU
]

## The kind of place; when not set, one of `biomes` is picked by the seed.
@export var biome: LocationBiome
@export var biomes: Array[LocationBiome] = []
## The ores it has, commonest first (set by the mission from its region); empty: the biome's.
@export var ores: Array[OreType] = []
## Same seed and biome, same world; 0: a new one every time.
@export var world_seed: int = 0
## How many open areas it has (the mission sets it by the region's length).
@export var area_count: int = 11
## Distance between the ground's grid points, in m.
@export var cell: float = 2.0
## Location-local area kept flat at height 0 for the ship, its ramp and the space in front of it.
@export var landing_site: Rect2 = Rect2(-96.0, -26.0, 146.0, 52.0)
## Where players step off the ramp, location-local x, z.
@export var ramp_exit: Vector2 = Vector2(20.0, 0.0)
## The landing yard in front of the ramp, where the passes start (x, z, radius).
@export var landing_yard: Vector3 = Vector3(66.0, 0.0, 36.0)
## How far from the ramp exit the first two ore fields lie (min, max), in m: found right away.
@export var near_ore_distance: Vector2 = Vector2(25.0, 55.0)
## Distance over which the flat landing site blends into the ground around it, in m.
@export var landing_falloff: float = 6.0
## Rock around the outermost areas, up to the edges, in m.
@export var rim_width: float = 40.0
## How much higher the rock rises towards the edges, in m.
@export var rim_height: float = 24.0
## Closest an ore field is to another one, in m.
@export var ore_field_spacing: float = 20.0
## Closest two nests are to each other, in m.
@export var nest_spacing: float = 20.0
## Closest a nest is to an ore node, in m.
@export var nest_ore_spacing: float = 12.0
## Scales the biome's number of nests (the mission's difficulty).
@export var nest_factor: float = 1.0
## Baked for the aliens once the world is generated (none without it).
@export var navigation_mesh: NavigationMesh

## The generated ground.
var terrain: LocationTerrain
## The plan the ground was carved from: its areas and passes.
var layout: LocationLayout
## Edge length of the square ground, in m (it grows with the layout).
var size: float = 0.0

var _rng := RandomNumberGenerator.new()
## Grid points players can walk to from the ship (1 = reachable).
var _reachable: PackedByteArray
## Grid points on a lane along a pass (1 = keep free).
var _lanes: PackedByteArray
## Areas whose open ground has its own shape (hollows, craters, plateaus).
var _shaped_areas: Array[LocationLayout.Area] = []
## Places scatter keeps away from (x, z, radius), location-local.
var _clearings: Array[Vector3] = []
## Location-local positions of the ore nodes, and of the nests, to be placed.
var _ore_sites: Array[Vector3] = []
var _ore_site_types: Array[OreType] = []
var _nest_sites: Array[Vector3] = []
## Planned ground chunks: name, mesh arrays and collision faces of each.
var _chunk_names: PackedStringArray = []
var _chunk_arrays: Array[Array] = []
var _chunk_faces: Array[PackedVector3Array] = []
## Planned scatter chunks: type, name and placements (`Transform3D`s) of each.
var _scatter_types: Array[ScatterType] = []
var _scatter_names: PackedStringArray = []
var _scatter_placements: Array[Array] = []
## Whether each planned scatter chunk lies on the rock (hidden where the cut-away presses it down).
var _scatter_on_rock: Array[bool] = []
var _planned: bool = false
var _built: bool = false


func _ready() -> void:
	build()


## Generates the world without adding nodes: safe on a worker thread while the location is outside
## the tree and nothing else touches it. Does nothing the second time.
func plan() -> void:
	if _planned:
		return
	while world_seed == 0:
		world_seed = randi()
	_rng.seed = world_seed
	if not biome:
		biome = biomes[_rng.randi() % biomes.size()]
	layout = LocationLayout.generate(
		_rng, area_count, biome, landing_yard, landing_site.grow(LANDING_MARGIN)
	)
	_generate_ground()
	_reachable = terrain.reachable_from(ramp_exit, MAX_WALK_SLOPE)
	_pick_ore_sites()
	_pick_nest_sites()
	# Flattening the sites changed the ground a little.
	_reachable = terrain.reachable_from(ramp_exit, MAX_WALK_SLOPE)
	_plan_ground()
	_plan_scatter()
	_planned = true


## Adds the planned world's nodes, planning it first if that hasn't happened yet. Does nothing the
## second time.
func build() -> void:
	if _built:
		return
	plan()
	_built = true
	_add_ground()
	_add_bounds()
	_add_scatter()
	_add_ore_nodes()
	_add_nests()
	if navigation_mesh:
		var navigation := LocationNavigation.new()
		navigation.name = "Navigation"
		navigation.navigation_mesh = navigation_mesh
		navigation.bake_in_background = true
		add_child(navigation)


## Whether `build` added the world's nodes.
func is_built() -> bool:
	return _built


## Whether players can walk from the ship to location-local `x`, `z`.
func is_reachable(x: float, z: float) -> bool:
	var grid: Vector2i = Vector2i(terrain.to_grid(Vector2(x, z)).round())
	if not Rect2i(0, 0, terrain.cells + 1, terrain.cells + 1).has_point(grid):
		return false
	return _reachable[terrain.index(grid.x, grid.y)] == 1


## Whether location-local `x`, `z` lies on a lane along a pass (kept free of blocking things).
func is_on_lane(x: float, z: float) -> bool:
	var grid: Vector2i = Vector2i(terrain.to_grid(Vector2(x, z)).round())
	if not Rect2i(0, 0, terrain.cells + 1, terrain.cells + 1).has_point(grid):
		return false
	return _lanes[terrain.index(grid.x, grid.y)] == 1


## Where the ore nodes go (location-local), and their ores: known once planned.
func planned_ore_sites() -> Array[Vector3]:
	return _ore_sites


func planned_ore_types() -> Array[OreType]:
	return _ore_site_types


## Where the nests go (location-local): known once planned.
func planned_nest_sites() -> Array[Vector3]:
	return _nest_sites


## Spots (location-local x, z) a player could fall to from walkable ground without a way back to
## the ship: should be none. A fall ends where the ground stops dropping steeply.
func stuck_spots() -> PackedVector2Array:
	var stuck := PackedVector2Array()
	var max_rise: float = MAX_WALK_SLOPE * cell
	var side: int = terrain.cells + 1
	for current: int in _reachable.size():
		if not _reachable[current]:
			continue
		var x: int = current % side
		@warning_ignore("integer_division")
		var z: int = current / side
		for next: Vector2i in _neighbors(x, z):
			var below: int = terrain.index(next.x, next.y)
			if _reachable[below] or terrain.heights[current] - terrain.heights[below] <= max_rise:
				continue
			var landed: Vector2i = _slide_down(next)
			if not _reachable[terrain.index(landed.x, landed.y)]:
				var at: Vector3 = terrain.point(landed.x, landed.y)
				stuck.append(Vector2(at.x, at.z))
	return stuck


## Where something falling onto grid point `from` comes to rest: down the steepest way while it's
## too steep to stand, until it reaches walkable ground.
func _slide_down(from: Vector2i) -> Vector2i:
	var max_rise: float = MAX_WALK_SLOPE * cell
	var at: Vector2i = from
	for step: int in terrain.cells * 2:
		if _reachable[terrain.index(at.x, at.y)]:
			return at
		var lowest: Vector2i = at
		for next: Vector2i in _neighbors(at.x, at.y):
			if terrain.get_height(next.x, next.y) < terrain.get_height(lowest.x, lowest.y):
				lowest = next
		var drop: float = terrain.get_height(at.x, at.y) - terrain.get_height(lowest.x, lowest.y)
		if lowest == at or drop <= max_rise * 0.5:
			return at
		at = lowest
	return at


func _neighbors(x: int, z: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var next: Vector2i = Vector2i(x, z) + offset
		if next.x >= 0 and next.y >= 0 and next.x <= terrain.cells and next.y <= terrain.cells:
			found.append(next)
	return found


func _generate_ground() -> void:
	var bounds: Rect2 = landing_site
	for area: LocationLayout.Area in layout.areas:
		bounds = bounds.merge(
			Rect2(area.center - Vector2.ONE * area.radius, Vector2.ONE * area.radius * 2.0)
		)
	var side: float = maxf(bounds.size.x, bounds.size.y) + (rim_width + biome.cliff_width) * 2.0
	var cells: int = ceili(side / cell)
	size = cells * cell
	terrain = LocationTerrain.new(bounds.get_center() - Vector2.ONE * size * 0.5, cells, cell)
	var wobble: FastNoiseLite = _noise(1.0 / 30.0, 2)
	var swells: FastNoiseLite = _noise(1.0 / biome.floor_relief_size, 3)
	var rock: FastNoiseLite = _noise(1.0 / 90.0, 3)
	var bumps: FastNoiseLite = _noise(1.0 / 12.0, 2)
	var outside: PackedFloat32Array = _distance_outside(_carve(wobble))
	for area: LocationLayout.Area in layout.areas:
		if area.kind in SHAPED_KINDS:
			_shaped_areas.append(area)
	for z: int in cells + 1:
		for x: int in cells + 1:
			var at := Vector2(terrain.origin.x + x * cell, terrain.origin.y + z * cell)
			var walls: float = _walls(outside[terrain.index(x, z)])
			var ground: float = _shape_of_areas(at, swells)
			var high: float = maxf(rock.get_noise_2dv(at) + 0.2, 0.0) * biome.rock_relief
			var height: float = ground + walls * (biome.wall_height + _terrace(high))
			height += bumps.get_noise_2dv(at) * biome.bump_height
			var to_edge: float = minf(minf(x, cells - x), minf(z, cells - z)) * cell
			var rim: float = 1.0 - smoothstep(0.0, rim_width, to_edge)
			height += rim * rim * rim_height
			terrain.set_height(x, z, height)
	# One grid square more, so the ground between the grid points inside is flat too.
	terrain.flatten_rect(landing_site.grow(cell), landing_falloff, 0.0)


## How open each grid point is: positive inside an area, a pass or around the landing site (how
## far inside, in m), negative outside. Also marks the lanes along the passes.
func _carve(wobble: FastNoiseLite) -> PackedFloat32Array:
	var openness := PackedFloat32Array()
	openness.resize(terrain.heights.size())
	openness.fill(-INF)
	_lanes = PackedByteArray()
	_lanes.resize(terrain.heights.size())
	# The outlines wobble by noise (about -1 to 1), so no area is a circle and no pass a tube.
	var bends := PackedFloat32Array()
	bends.resize(terrain.heights.size())
	for z: int in terrain.cells + 1:
		for x: int in terrain.cells + 1:
			var at := Vector2(terrain.origin.x + x * cell, terrain.origin.y + z * cell)
			bends[terrain.index(x, z)] = clampf(wobble.get_noise_2dv(at) * 2.0, -1.0, 1.0)
	var reach: float = biome.cliff_width + cell
	var site: Rect2 = landing_site.grow(LANDING_MARGIN + reach)
	var low: Vector2i = Vector2i(terrain.to_grid(site.position).floor()).maxi(0)
	var high: Vector2i = Vector2i(terrain.to_grid(site.end).ceil()).mini(terrain.cells)
	for z: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var at := Vector2(terrain.origin.x + x * cell, terrain.origin.y + z * cell)
			openness[terrain.index(x, z)] = LANDING_MARGIN - _distance_to_landing_site(at)
	for area: LocationLayout.Area in layout.areas:
		# A plateau's outline only wobbles outwards, so its cliff never closes in on the mesa (from its
		# top the rock would be a small step).
		var outward: bool = area.kind == LocationLayout.Kind.PLATEAU
		_stamp(openness, bends, area.center, area.radius, AREA_WOBBLE, outward)
	_mark_lane(ramp_exit, Vector2(landing_yard.x, landing_yard.y))
	for way: LocationLayout.Pass in layout.passes:
		var ends: Array[LocationLayout.Area] = [layout.areas[way.from], layout.areas[way.to]]
		for i: int in way.points.size():
			_stamp(openness, bends, way.points[i], way.width * 0.5, PASS_WOBBLE)
			if i > 0 and not _in_middle(way.points[i], ends):
				_mark_lane(way.points[i - 1], way.points[i])
	return openness


## How much of the wall stands at `distance` m from the open ground: 0 on it, 1 on the rock. The
## first grid point off the open ground already has `FIRST_STEP` of it, so no step from the open
## ground onto the rock is walkable, however the grid lies along the cliff.
func _walls(distance: float) -> float:
	if distance <= 0.0:
		return 0.0
	var full: float = maxf(biome.cliff_width, cell * 1.5)
	return lerpf(FIRST_STEP, 1.0, smoothstep(cell, full, distance))


## How far each grid point lies from the open ground (`openness` above 0), in m: 0 on it. The
## cliffs rise over this distance, so they're equally steep everywhere, however the outlines wobble.
func _distance_outside(openness: PackedFloat32Array) -> PackedFloat32Array:
	var side: int = terrain.cells + 1
	var distance := PackedFloat32Array()
	distance.resize(openness.size())
	for i: int in openness.size():
		distance[i] = 0.0 if openness[i] > 0.0 else INF
	# Two sweeps (chamfer distance: straight steps 1, diagonal ones √2 grid squares).
	var steps: Array[Vector3i] = [
		Vector3i(-1, 0, 10), Vector3i(0, -1, 10), Vector3i(-1, -1, 14), Vector3i(1, -1, 14)
	]
	for sweep: int in 2:
		var direction: int = 1 if sweep == 0 else -1
		for row: int in side:
			var z: int = row if sweep == 0 else side - 1 - row
			for column: int in side:
				var x: int = column if sweep == 0 else side - 1 - column
				var index: int = z * side + x
				for step: Vector3i in steps:
					var nx: int = x + step.x * direction
					var nz: int = z + step.y * direction
					if nx < 0 or nz < 0 or nx >= side or nz >= side:
						continue
					var through: float = distance[nz * side + nx] + step.z * 0.1
					if through < distance[index]:
						distance[index] = through
	for i: int in distance.size():
		distance[i] *= cell
	return distance


## Raises `openness` around `center` to a round outline of `radius`, wobbling by `wobble` (a share
## of the radius) with `bends` (only outwards with `outward_only`).
func _stamp(
	openness: PackedFloat32Array,
	bends: PackedFloat32Array,
	center: Vector2,
	radius: float,
	wobble: float,
	outward_only: bool = false
) -> void:
	var reach: float = radius * (1.0 + wobble) + biome.cliff_width + cell
	var low: Vector2i = Vector2i(terrain.to_grid(center - Vector2.ONE * reach).floor()).maxi(0)
	var high: Vector2i = Vector2i(terrain.to_grid(center + Vector2.ONE * reach).ceil()).mini(
		terrain.cells
	)
	for z: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var index: int = terrain.index(x, z)
			var at := Vector2(terrain.origin.x + x * cell, terrain.origin.y + z * cell)
			var bend: float = maxf(bends[index], 0.0) if outward_only else bends[index]
			var inside: float = radius * (1.0 + bend * wobble) - at.distance_to(center)
			openness[index] = maxf(openness[index], inside)


## Whether `at` lies in the middle of one of `areas`: open enough to walk around anything there,
## so the lanes end before it.
func _in_middle(at: Vector2, areas: Array[LocationLayout.Area]) -> bool:
	for area: LocationLayout.Area in areas:
		if at.distance_to(area.center) < area.radius * LANE_FREE_MIDDLE:
			return true
	return false


## Marks the grid points within `LANE_HALF_WIDTH` of the line from `from` to `to`.
func _mark_lane(from: Vector2, to: Vector2) -> void:
	var low: Vector2 = terrain.to_grid(from.min(to) - Vector2.ONE * LANE_HALF_WIDTH).floor()
	var high: Vector2 = terrain.to_grid(from.max(to) + Vector2.ONE * LANE_HALF_WIDTH).ceil()
	for z: int in range(maxi(int(low.y), 0), mini(int(high.y), terrain.cells) + 1):
		for x: int in range(maxi(int(low.x), 0), mini(int(high.x), terrain.cells) + 1):
			var at := Vector2(terrain.origin.x + x * cell, terrain.origin.y + z * cell)
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(at, from, to)
			if at.distance_to(closest) <= LANE_HALF_WIDTH:
				_lanes[terrain.index(x, z)] = 1


## The open ground's height at location-local `at`, in m: gentle swells (`swells`), and their own
## shape in special areas: nest hollows sink, craters
## are bowls with a rim, plateaus have a mesa with a ramp up its side.
func _shape_of_areas(at: Vector2, swells: FastNoiseLite) -> float:
	var ground: float = swells.get_noise_2dv(at) * biome.floor_relief
	var offset: float = 0.0
	for area: LocationLayout.Area in _shaped_areas:
		var distance: float = at.distance_to(area.center)
		if distance > area.radius * (1.0 + AREA_WOBBLE):
			continue
		match area.kind:
			LocationLayout.Kind.NEST_HOLLOW:
				offset -= (
					HOLLOW_DEPTH
					* (1.0 - smoothstep(area.radius * 0.3, area.radius * 0.9, distance))
				)
			LocationLayout.Kind.CRATER:
				var bowl: float = 1.0 - smoothstep(0.0, area.radius * 0.5, distance)
				var rim: float = exp(-pow(distance - area.radius * 0.55, 2.0) / 18.0)
				offset += rim * CRATER_RIM - bowl * CRATER_DEPTH
			LocationLayout.Kind.PLATEAU:
				# A level top, `MESA_HEIGHT` above the open ground at the mesa's center.
				var mesa_center := Vector2(area.mesa.x, area.mesa.y)
				var top: float = (
					swells.get_noise_2dv(mesa_center) * biome.floor_relief
					+ LocationLayout.MESA_HEIGHT
				)
				ground = lerpf(ground, top, _mesa(area, at))
	return ground + offset


## How far up a plateau's mesa location-local `at` is: 1 on its top, 0 off it, rising along the
## ramp.
func _mesa(area: LocationLayout.Area, at: Vector2) -> float:
	var mesa_center := Vector2(area.mesa.x, area.mesa.y)
	var up: float = 1.0 - smoothstep(area.mesa.z - cell, area.mesa.z, at.distance_to(mesa_center))
	var along: float = (at - area.ramp_start).dot(area.ramp_direction)
	var across: float = absf((at - area.ramp_start).cross(area.ramp_direction))
	if (
		along >= 0.0
		and along <= area.ramp_length + cell
		and across <= LocationLayout.RAMP_WIDTH * 0.5
	):
		up = maxf(up, minf(along / area.ramp_length, 1.0))
	return up


## Flat steps of `biome.plateau_step`, with a steep rise between them.
func _terrace(height: float) -> float:
	var steps: float = height / biome.plateau_step
	var base: float = floorf(steps)
	return (base + smoothstep(0.8, 1.0, steps - base)) * biome.plateau_step


func _noise(frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = _rng.randi()
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	return noise


func _distance_to_landing_site(at: Vector2) -> float:
	var offset: Vector2 = (at - landing_site.get_center()).abs() - landing_site.size * 0.5
	return offset.max(Vector2.ZERO).length()


## Ore fields: a few nodes of one type close together, in the areas. The first two are close to
## the ramp and have the commonest ore; every ore pocket gets the rarest; the rest spread over the
## other areas (not the nest hollows), rarer the farther they lie along the passes.
func _pick_ore_sites() -> void:
	var found: Array[OreType] = ores if not ores.is_empty() else OreCatalog.sorted(biome.ores)
	if found.is_empty():
		return
	var landing: LocationLayout.Area = layout.areas[0]
	_add_ore_field(found[0], landing, true)
	_add_ore_field(found[0], landing, true)
	var others: Array[LocationLayout.Area] = []
	for area: LocationLayout.Area in layout.areas:
		if area.kind == LocationLayout.Kind.ORE_POCKET:
			_add_ore_field(found[found.size() - 1], area, false)
		elif area.kind not in [LocationLayout.Kind.LANDING, LocationLayout.Kind.NEST_HOLLOW]:
			others.append(area)
	var wanted: int = roundi(layout.areas.size() * biome.ore_fields_per_area)
	var farthest: float = maxf(layout.farthest(), 1.0)
	var fields: int = 0
	for attempt: int in wanted * 3:
		if others.is_empty() or fields >= wanted:
			break
		var area: LocationLayout.Area = others[_rng.randi() % others.size()]
		var rank: float = area.distance / farthest * found.size() + _rng.randf_range(-0.6, 0.6)
		var ore_type: OreType = found[clampi(int(rank), 0, found.size() - 1)]
		if _add_ore_field(ore_type, area, false):
			fields += 1


## Adds an ore field of `ore_type` in `area` (`near`: close to the ramp); false when there's no
## room.
func _add_ore_field(ore_type: OreType, area: LocationLayout.Area, near: bool) -> bool:
	var fields: Array[Vector3] = []
	for site: Vector3 in _ore_sites:
		fields.append(site)
	var center: Vector3 = _find_site(
		ORE_SITE_RADIUS,
		func(at: Vector2) -> bool:
			if near and at.distance_to(ramp_exit) < near_ore_distance.x:
				return false
			return (
				_distance_to_landing_site(at) >= 10.0 and _far_from(at, fields, ore_field_spacing)
			),
		ramp_exit if near else area.center,
		near_ore_distance.y if near else area.radius * 0.8
	)
	if center == Vector3.INF:
		return false
	var count: int = _rng.randi_range(biome.ore_nodes_per_field.x, biome.ore_nodes_per_field.y)
	for node: int in count:
		var site: Vector3 = Vector3(center.x, 0.0, center.z)
		if node > 0:
			site = _find_site(
				ORE_SITE_RADIUS,
				func(at: Vector2) -> bool:
					return _distance_to_landing_site(at) >= 10.0 and _far_from(at, _ore_sites, 7.0),
				Vector2(center.x, center.z),
				12.0
			)
		if site == Vector3.INF:
			continue
		_add_site(site, ORE_SITE_RADIUS, 1.5)
		_ore_sites.append(Vector3(site.x, terrain.height_at(site.x, site.z), site.z))
		_ore_site_types.append(ore_type)
	return true


## Nests in the areas far enough from the ship: two in every nest hollow first, then spread over
## the others, the areas every way out goes through last (so they rarely block the way back).
func _pick_nest_sites() -> void:
	var wanted: int = roundi(layout.areas.size() * biome.nests_per_area * nest_factor)
	var cut: PackedInt32Array = layout.cut_areas()
	var first: Array[LocationLayout.Area] = []
	var spread: Array[LocationLayout.Area] = []
	var last: Array[LocationLayout.Area] = []
	for i: int in layout.areas.size():
		var area: LocationLayout.Area = layout.areas[i]
		if area.kind == LocationLayout.Kind.LANDING or area.distance < biome.nest_min_distance:
			continue
		if area.kind == LocationLayout.Kind.NEST_HOLLOW:
			first.append(area)
			first.append(area)
		elif i in cut:
			last.append(area)
		else:
			spread.append(area)
	var order: Array[LocationLayout.Area] = first
	order.append_array(_shuffled(spread))
	order.append_array(_shuffled(last))
	if order.is_empty():
		return
	for attempt: int in maxi(wanted, order.size()) * 3:
		if _nest_sites.size() >= wanted:
			break
		var area: LocationLayout.Area = order[attempt % order.size()]
		var site: Vector3 = _find_site(
			NEST_SITE_RADIUS,
			func(at: Vector2) -> bool:
				return (
					_distance_to_landing_site(at) >= biome.nest_min_distance * NEST_STRAIGHT_SHARE
					and _far_from(at, _nest_sites, nest_spacing)
					and _far_from(at, _ore_sites, nest_ore_spacing)
				),
			area.center,
			area.radius * 0.8
		)
		if site == Vector3.INF:
			continue
		_add_site(site, NEST_SITE_RADIUS, 3.5)
		_nest_sites.append(Vector3(site.x, terrain.height_at(site.x, site.z), site.z))


func _shuffled(areas: Array[LocationLayout.Area]) -> Array[LocationLayout.Area]:
	var mixed: Array[LocationLayout.Area] = areas.duplicate()
	for i: int in range(mixed.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var swap: LocationLayout.Area = mixed[i]
		mixed[i] = mixed[j]
		mixed[j] = swap
	return mixed


## A reachable, gentle spot off the lanes where `fits` agrees, within `spread` of `around`;
## `Vector3.INF` when there is none.
func _find_site(radius: float, fits: Callable, around: Vector2, spread: float) -> Vector3:
	var area: Rect2 = terrain.rect().grow(-rim_width - radius)
	for attempt: int in PLACEMENT_TRIES:
		var at: Vector2 = (
			around + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, spread)
		)
		if area.has_point(at) and fits.call(at) and _is_gentle(at, radius):
			return Vector3(at.x, 0.0, at.y)
	return Vector3.INF


## Whether the ground within `radius` of `at` is reachable, off the lanes and even enough to build
## on, and flattening it changes no step from walkable to too steep or back.
func _is_gentle(at: Vector2, radius: float) -> bool:
	var points: Array[Vector2i] = _grid_within(at, radius)
	if points.is_empty():
		return false
	var lowest: float = INF
	var highest: float = -INF
	for point: Vector2i in points:
		var index: int = terrain.index(point.x, point.y)
		if _lanes[index] or not _reachable[index]:
			return false
		lowest = minf(lowest, terrain.heights[index])
		highest = maxf(highest, terrain.heights[index])
	if highest - lowest > MAX_SITE_RISE * radius * 2.0:
		return false
	return _flattening_keeps_steps(at, radius)


## Whether flattening a site of `radius` at `at` (see `_add_site`) leaves every step between
## neighboring grid points as it was: walkable ones walkable, too steep ones too steep.
func _flattening_keeps_steps(at: Vector2, radius: float) -> bool:
	var level: float = terrain.height_at(at.x, at.y)
	var max_rise: float = MAX_WALK_SLOPE * cell
	var changed: Dictionary[int, float] = {}
	var around: Array[Vector2i] = _grid_within(at, radius + SITE_FALLOFF + cell)
	if around.is_empty():
		return false
	for point: Vector2i in around:
		var index: int = terrain.index(point.x, point.y)
		var spot: Vector3 = terrain.point(point.x, point.y)
		var outside: float = Vector2(spot.x, spot.z).distance_to(at) - radius
		var weight: float = 1.0 - smoothstep(0.0, SITE_FALLOFF, outside)
		changed[index] = lerpf(terrain.heights[index], level, weight)
	for point: Vector2i in around:
		var index: int = terrain.index(point.x, point.y)
		for next: Vector2i in _neighbors(point.x, point.y):
			var other: int = terrain.index(next.x, next.y)
			var before: float = absf(terrain.heights[index] - terrain.heights[other])
			var next_height: float = (
				changed[other] if changed.has(other) else terrain.heights[other]
			)
			var after: float = absf(changed[index] - next_height)
			if (before <= max_rise) != (after <= max_rise):
				return false
	return true


## The grid points within `radius` of `at`; empty when some lie off the ground.
func _grid_within(at: Vector2, radius: float) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var low: Vector2 = terrain.to_grid(at - Vector2.ONE * radius).floor()
	var high: Vector2 = terrain.to_grid(at + Vector2.ONE * radius).ceil()
	for z: int in range(int(low.y), int(high.y) + 1):
		for x: int in range(int(low.x), int(high.x) + 1):
			if x < 0 or z < 0 or x > terrain.cells or z > terrain.cells:
				return [] as Array[Vector2i]
			var point: Vector3 = terrain.point(x, z)
			if Vector2(point.x, point.z).distance_to(at) <= radius:
				points.append(Vector2i(x, z))
	return points


func _far_from(at: Vector2, sites: Array[Vector3], distance: float) -> bool:
	for site: Vector3 in sites:
		if at.distance_to(Vector2(site.x, site.z)) < distance:
			return false
	return true


## Flattens the ground at `site` and keeps scatter away from it (`room` m beyond `radius`).
func _add_site(site: Vector3, radius: float, room: float) -> void:
	var at := Vector2(site.x, site.z)
	terrain.flatten(at, radius, SITE_FALLOFF, terrain.height_at(at.x, at.y))
	_clearings.append(Vector3(site.x, site.z, radius + room))


## The ground's chunks: their mesh arrays (painted) and collision faces.
func _plan_ground() -> void:
	var shades: FastNoiseLite = _noise(1.0 / 40.0, 2)
	var patches: FastNoiseLite = _noise(1.0 / 18.0, 2)
	var highest: PackedFloat32Array = terrain.highest_around(SCREE_REACH)
	var paint: Callable = func(point: Vector3, _up: Vector3) -> Color:
		return _ground_paint(point, shades, patches, highest)
	var chunks: int = ceili(float(terrain.cells) / CHUNK_CELLS)
	for chunk_z: int in chunks:
		for chunk_x: int in chunks:
			var from := Vector2i(chunk_x, chunk_z) * CHUNK_CELLS
			var to: Vector2i = (from + Vector2i.ONE * CHUNK_CELLS).min(Vector2i.ONE * terrain.cells)
			_chunk_names.append("Chunk%d_%d" % [chunk_x, chunk_z])
			_chunk_arrays.append(terrain.build_arrays(from, to, paint))
			_chunk_faces.append(terrain.build_faces(from, to))


func _add_ground() -> void:
	var ground := Node3D.new()
	ground.name = "Ground"
	add_child(ground)
	var material: Material = biome.ground_material
	if not material:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.3, 0.27, 0.23)
		plain.vertex_color_use_as_albedo = true
		plain.roughness = 1.0
		material = plain
	for i: int in _chunk_names.size():
		var body := StaticBody3D.new()
		body.name = _chunk_names[i]
		var array_mesh := ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _chunk_arrays[i])
		var mesh := MeshInstance3D.new()
		mesh.mesh = array_mesh
		mesh.material_override = material
		body.add_child(mesh)
		var faces := ConcavePolygonShape3D.new()
		faces.set_faces(_chunk_faces[i])
		var shape := CollisionShape3D.new()
		shape.shape = faces
		body.add_child(shape)
		ground.add_child(body)
	_chunk_arrays.clear()
	_chunk_faces.clear()


## Vertex color of the ground at `point`: RGB a tint (lighter on the rock, varying over large
## areas), A the share of scree (at the foot of steep ground and in patches).
## `highest`: the highest ground around each grid point (`LocationTerrain.highest_around`).
func _ground_paint(
	point: Vector3, shades: FastNoiseLite, patches: FastNoiseLite, highest: PackedFloat32Array
) -> Color:
	var high: float = smoothstep(0.0, biome.wall_height, point.y)
	var tint: Color = biome.low_ground_tint.lerp(Color.WHITE, high)
	var at := Vector2(point.x, point.z)
	tint *= 1.0 + shades.get_noise_2dv(at) * 2.0 * biome.tint_variation
	# Scree collects where the ground rises steeply close by.
	var grid := Vector2i(terrain.to_grid(at).round())
	var rise: float = highest[terrain.index(grid.x, grid.y)] - point.y
	var foot: float = smoothstep(1.5, 3.5, rise)
	var patch: float = smoothstep(0.3, 0.5, patches.get_noise_2dv(at))
	patch *= smoothstep(5.0, 20.0, _distance_to_landing_site(at))
	tint.a = clampf((foot + patch) * biome.scree * 2.0, 0.0, 1.0)
	return tint


## Invisible walls along the edges.
func _add_bounds() -> void:
	var bounds := StaticBody3D.new()
	bounds.name = "Bounds"
	add_child(bounds)
	var area: Rect2 = terrain.rect()
	var center: Vector2 = area.get_center()
	var half: float = area.size.x * 0.5
	for side: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var box := BoxShape3D.new()
		box.size = Vector3(
			area.size.x + 2.0 if side.x == 0.0 else 1.0,
			BOUNDS_HEIGHT,
			area.size.y + 2.0 if side.y == 0.0 else 1.0
		)
		var shape := CollisionShape3D.new()
		shape.shape = box
		var at: Vector2 = center + side * (half + 0.5)
		shape.position = Vector3(at.x, 0.0, at.y)
		bounds.add_child(shape)


func _add_scatter() -> void:
	var scatter := Node3D.new()
	scatter.name = "Scatter"
	add_child(scatter)
	var cutaway := ScatterCutaway.new()
	cutaway.name = "Cutaway"
	scatter.add_child(cutaway)
	for i: int in _scatter_types.size():
		var placements: Array = _scatter_placements[i]
		var mesh: MultiMesh = _add_scatter_chunk(
			scatter, _scatter_types[i], _scatter_names[i], placements
		)
		if mesh and _scatter_on_rock[i]:
			cutaway.watch(mesh, placements)
	_scatter_placements.clear()


## Where the plants and rocks grow, by type and chunk (the ones on the rock in their own chunks).
func _plan_scatter() -> void:
	var chunk_size: float = CHUNK_CELLS * cell
	var blockers: Array[Vector3] = []
	for type: ScatterType in biome.scatter:
		var by_chunk: Dictionary[Vector3i, Array] = {}
		for placed: Transform3D in _scatter_transforms(type, blockers):
			var at := Vector2(placed.origin.x, placed.origin.z)
			var grid: Vector2i = Vector2i(((at - terrain.origin) / chunk_size).floor())
			var chunk := Vector3i(grid.x, grid.y, 0 if is_reachable(at.x, at.y) else 1)
			if not by_chunk.has(chunk):
				by_chunk[chunk] = []
			by_chunk[chunk].append(placed)
		for chunk: Vector3i in by_chunk:
			var on_rock: bool = chunk.z == 1
			_scatter_types.append(type)
			_scatter_names.append(
				(
					"%s%d_%d%s"
					% [
						type.display_name.to_pascal_case(),
						chunk.x,
						chunk.y,
						"Rock" if on_rock else ""
					]
				)
			)
			_scatter_placements.append(by_chunk[chunk])
			_scatter_on_rock.append(on_rock)


## Where `type` grows: on a jittered grid, thinned out by patches, steep ground and clearings.
## Blocking ones keep their distance from each other (`blockers`: x, z, radius) and off the lanes.
func _scatter_transforms(type: ScatterType, blockers: Array[Vector3]) -> Array[Transform3D]:
	var placed: Array[Transform3D] = []
	if type.density <= 0.0 or not type.has_mesh():
		return placed
	var spacing: float = sqrt(100.0 / type.density)
	var patches: FastNoiseLite = _noise(1.0 / type.patch_size, 2)
	var steps: int = floori(terrain.size() / spacing)
	for row: int in steps:
		for column: int in steps:
			var at: Vector2 = (
				terrain.origin
				+ (Vector2(column, row) + Vector2(_rng.randf(), _rng.randf())) * spacing
			)
			var patch: float = smoothstep(-0.05, 0.15, patches.get_noise_2dv(at))
			if _rng.randf() > lerpf(1.0, patch, type.clustering):
				continue
			var grown: float = _rng.randf_range(type.min_scale, type.max_scale)
			var radius: float = type.blocking_radius * grown
			if not _can_scatter(at, type.max_slope, radius, blockers):
				continue
			if radius > 0.0:
				blockers.append(Vector3(at.x, at.y, radius))
			var tilt: float = deg_to_rad(_rng.randf_range(-type.max_tilt, type.max_tilt))
			var turn := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, tilt)
			var height: float = terrain.height_at(at.x, at.y) - type.sink * grown
			placed.append(
				Transform3D(turn.scaled(Vector3.ONE * grown), Vector3(at.x, height, at.y))
			)
	return placed


func _can_scatter(at: Vector2, max_slope: float, radius: float, blockers: Array[Vector3]) -> bool:
	if not terrain.rect().grow(-cell).has_point(at):
		return false
	if _distance_to_landing_site(at) < 4.0 + radius:
		return false
	var grid: Vector2i = Vector2i(terrain.to_grid(at).round())
	var on_lane: bool = radius > 0.0 and _lanes[terrain.index(grid.x, grid.y)] == 1
	if on_lane or terrain.slope(grid.x, grid.y) > max_slope:
		return false
	for clearing: Vector3 in _clearings:
		if at.distance_to(Vector2(clearing.x, clearing.y)) < clearing.z + radius:
			return false
	if radius > 0.0:
		for blocker: Vector3 in blockers:
			if at.distance_squared_to(Vector2(blocker.x, blocker.y)) < pow(blocker.z + radius, 2):
				return false
	return true


## Adds a chunk of `type` at `transforms`; returns its multimesh (null without a mesh).
func _add_scatter_chunk(
	parent: Node3D, type: ScatterType, chunk_name: String, transforms: Array
) -> MultiMesh:
	if not type.get_mesh():
		return null
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
		return multimesh
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
	return multimesh


func _add_ore_nodes() -> void:
	var ore_nodes := Node3D.new()
	ore_nodes.name = "OreNodes"
	add_child(ore_nodes)
	for i: int in _ore_sites.size():
		var node := ORE_NODE.instantiate() as OreNode
		node.name = "Ore%d" % (i + 1)
		node.ore_type = _ore_site_types[i]
		node.variant = i
		node.position = _ore_sites[i]
		node.rotation.y = _rng.randf() * TAU
		ore_nodes.add_child(node)


func _add_nests() -> void:
	var nests := Node3D.new()
	nests.name = "AlienNests"
	add_child(nests)
	for i: int in _nest_sites.size():
		var nest := ALIEN_NEST.instantiate() as AlienNest
		nest.name = "Nest%d" % (i + 1)
		nest.position = _nest_sites[i]
		nests.add_child(nest)
