class_name GeneratedLocation
extends Node3D
## An outside world generated from a seed and a biome when it appears (every run gets a fresh
## one): open areas joined by passes (a `LocationLayout`), carved into the biome's barrier (high
## rock nobody can climb, or gaps lowered below the floor with walls along their edges; with
## terraces, every area on a slab of its own level), with plants and rocks (`LocationScatter`),
## ore fields, alien nests and the biome's hazard. The ship
## stands at the location's origin, on a flat landing site; the location's axes are the ship's
## (nose to -x, ramp to +x). Ores and nests only lie where players can walk to from the ship; rarer
## ores lie farther along the passes, the rarest in dead ends. Every walkable spot leads back to the
## ship: there are no pits to fall into (a gap's edge is walled off, see `LocationGaps`). Some areas
## hold a point of interest or one of the region's set pieces (see `LocationParts`); their markers
## place ore, nests and crates first. A far one is the late deposit's impact site (`LateDeposit`):
## its crater is carved from the start, its meteorite and ore appear with the impact.
## What the active quest steps need here (`quest_visit`) comes in too: their quest sites as set
## pieces (at each one's quest anchor a `QuestSite`, or a hunt's brood nest or the Ravager asleep
## in its lair) and their quest nests after the ordinary ones.
## Everything the generator places is greybox; the values are TBD (playtest).
## The layout, the parts, the ground's shape and the hazard draw one after another from the seed
## itself; the ore fields, the nests and everything after them each draw from a random stream of
## their own (`random_stream`), so a stage added later, or one that draws more, leaves what the
## others pick as it was.
## Generating takes a while, so it runs in two steps: `plan` does the heavy work without touching
## nodes or servers, so it can run on a worker thread while the location is outside the tree (the
## ship prepares the next location before and during the flight); `build` then adds the nodes. A
## location that enters the tree unbuilt does both right away.

const ORE_NODE: PackedScene = preload("res://game/mining/ore_node.tscn")
const ALIEN_NEST: PackedScene = preload("res://game/aliens/nest/alien_nest.tscn")
const QUEST_NEST: PackedScene = preload("res://game/aliens/nest/quest_nest.tscn")
const HIVE: AlienHive = preload("res://game/aliens/hive/hive.tres")
const LATE_DEPOSIT: PartPlacement = preload("res://game/locations/parts/late_deposit.tres")
## Grid squares per chunk side: the ground and the scatter are cut into chunks so the parts out of
## view are culled.
const CHUNK_CELLS: int = 25
## Steepest slope players and aliens walk up, in rise per m (about 40°).
const MAX_WALK_SLOPE: float = 0.84
## How much the ground under an ore node or nest may rise from its lowest to its highest point
## (relative to the site's radius) before it's flattened.
const MAX_SITE_RISE: float = 0.3
## Height of the invisible walls at the edges, in m.
const BOUNDS_HEIGHT: float = 60.0
## How often a placement looks for a fitting spot before giving up.
const PLACEMENT_TRIES: int = 300
## How far (in grid points) the ground is checked for higher ground nearby when painting scree.
const SCREE_REACH: int = 2
## How much an area's outline wobbles, relative to its radius (a pass's: `LocationBiome`).
const AREA_WOBBLE: float = 0.2
## Open ground around the landing site, in m: more than `landing_falloff`, so the flat site never
## pulls the rock down into a ramp.
const LANDING_MARGIN: float = 10.0
## Distance over which the ground flattened under an ore node or nest blends back, in m.
const SITE_FALLOFF: float = 3.0
## The apex roams only between areas at least this far from the landing site (straight, m).
const APEX_LANDING_DISTANCE: float = 40.0
## Ground around the biome's hazard that ore, nests and map parts keep off as well, in m.
const HAZARD_MARGIN: float = 3.0
## Over how many m a raised bridge (`LocationBiome.bridge_rise`) rises from the areas it joins.
const BRIDGE_RAMP: float = 5.0
## Over how many m beyond the areas the rock beside a slot canyon rises to its full depth
## (`LocationBiome.canyon_depth`): from where it starts to where it's full, measured from how much
## farther the areas are than the canyon.
const CANYON_FADE: Vector2 = Vector2(4.0, 16.0)
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
## Where the camera looks, location-local (its forward direction; the mission sets it from where
## the ship lands). The rock between the camera and the open ground stays low enough to see over:
## a ledge (`LocationBiome.near_wall_height`), then rising no steeper than the view. Zero: the
## rock is equally high all around.
@export var view_direction: Vector3 = Vector3.ZERO
## Scales the biome's number of nests (the mission's difficulty).
@export var nest_factor: float = 1.0
## What its nests hatch (see `AlienHive.table`): the body's tier, and whether the region is hard
## enough to preview a strain of the next tier (the mission sets both).
@export var alien_tier: int = 1
@export var preview_strain: bool = false
## The region's set pieces: always placed (the mission sets them).
@export var set_pieces: Array[PartPlacement] = []
## The late deposit's part and where it goes (see `LateDeposit`); null: none.
@export var late_deposit: PartPlacement = LATE_DEPOSIT
## Baked for the aliens once the world is generated (none without it).
@export var navigation_mesh: NavigationMesh

## The generated ground.
var terrain: LocationTerrain
## The plan the ground was carved from: its areas and passes.
var layout: LocationLayout
## Edge length of the square ground, in m (it grows with the layout).
var size: float = 0.0
## Its points of interest and set pieces.
var parts := LocationParts.new()
## Where its ore nodes and nests go.
var sites := LocationSites.new(self)
## What the active quest steps put into this visit (see `QuestVisit`), or null; set before `plan`.
var quest_visit: QuestVisit
## The ground along its passes: their lanes, the ramps between terraces and the trails' paths.
var passes: LocationPasses

## Grid points players can walk to from the ship (1 = reachable).
var _reachable: PackedByteArray
## Grid points on a lane along a pass (1 = keep free; `passes.lanes`).
var _lanes: PackedByteArray
## Grid points on the rock on the camera's side of the open ground (1 = only low scatter).
var _camera_side: PackedByteArray
## Its gaps (null without them), and the grid points behind the walls along their edges (1 = a gap
## or its lip; empty without gaps).
var _gaps: LocationGaps
var _blocked: PackedByteArray
## Grid points on a bridge: on a pass, outside the areas (1); empty without bridges. How much a
## raised bridge lifts them, in m (empty unless raised).
var _bridges: PackedByteArray
var _bridge_lift: PackedFloat32Array
## The level of the open ground at each grid point (terraces), in m: its area's, rising along the
## ramps between them; elsewhere the nearest open ground's. Empty without terraces.
var _levels: PackedFloat32Array
## How far each grid point lies from the areas (not the passes), in m: for slot canyons only.
var _from_areas: PackedFloat32Array
## The biome's hazard.
var _hazards := LocationHazards.new(self)
## The ground of its special areas.
var _features := LocationFeatures.new(self)
## Places scatter keeps away from (x, z, radius), location-local.
var _clearings: Array[Vector3] = []
## Planned ground chunks: name, mesh arrays and collision faces of each.
var _chunk_names: PackedStringArray = []
var _chunk_arrays: Array[Array] = []
var _chunk_faces: Array[PackedVector3Array] = []
## Its plants and rocks.
var _scatter := LocationScatter.new()
var _planned: bool = false
var _built: bool = false
## What the nests hatch here, once made (see `_hatch_table`).
var _table: HatchTable


func _ready() -> void:
	build()


## Generates the world without adding nodes: safe on a worker thread while the location is outside
## the tree and nothing else touches it. Does nothing the second time.
func plan() -> void:
	if _planned:
		return
	while world_seed == 0:
		world_seed = randi()
	if not biome:
		biome = biomes[_stream("biome").randi() % biomes.size()]
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	layout = LocationLayout.generate(
		rng, area_count, biome, landing_yard, landing_site.grow(LANDING_MARGIN)
	)
	var pieces: Array[PartPlacement] = set_pieces.duplicate()
	if quest_visit:
		pieces.append_array(quest_visit.sites())
	parts.choose(rng, layout, pieces, biome.part_pool, biome.parts_per_area, late_deposit)
	_generate_ground(rng)
	_reachable = terrain.reachable_from(ramp_exit, MAX_WALK_SLOPE, _blocked)
	parts.settle(rng, self)
	_reachable = terrain.reachable_from(ramp_exit, MAX_WALK_SLOPE, _blocked)
	_hazards.place(rng)
	sites.pick(ores if not ores.is_empty() else OreCatalog.sorted(biome.ores))
	_reachable = terrain.reachable_from(ramp_exit, MAX_WALK_SLOPE, _blocked)
	if _gaps:
		_gaps.plan(_reachable, _stream("gaps"))
	_plan_ground()
	_scatter.plan(_stream("scatter"), self)
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
	if _gaps:
		_gaps.build(self)
	_hazards.build(self)
	_scatter.build(self)
	parts.build(self, _crate_contents())
	var late_ores: Array[OreNode] = _add_ore_nodes()
	_add_nests()
	_add_quest_sites()
	_add_late_deposit(late_ores)
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


## Whether location-local `x`, `z` lies in a gap (lowered, behind the walls along its edge).
func is_gap(x: float, z: float) -> bool:
	return _gaps != null and _flag(_gaps.gaps, x, z)


## Whether location-local `x`, `z` lies on a bridge (on a pass, outside the areas).
func is_on_bridge(x: float, z: float) -> bool:
	return _flag(_bridges, x, z)


## Whether location-local `at` lies in an area of one of `kinds`.
func is_in_area_of(at: Vector2, kinds: Array[LocationLayout.Kind]) -> bool:
	for area: LocationLayout.Area in layout.areas:
		if area.kind in kinds and at.distance_to(area.center) < area.radius * (1.0 + AREA_WOBBLE):
			return true
	return false


## Where the biome's hazard lies (x, z, radius), location-local: known once planned.
func planned_hazards() -> Array[Vector3]:
	return _hazards.spots


## Whether location-local `at` lies within `reach` m of the biome's hazard or the ground around
## it (`HAZARD_MARGIN`; a negative `reach` of as much: on the hazard).
func near_hazard(at: Vector2, reach: float) -> bool:
	for hazard: Vector3 in _hazards.spots:
		if at.distance_to(Vector2(hazard.x, hazard.y)) < hazard.z + HAZARD_MARGIN + reach:
			return true
	return false


## The walls along the gaps' edges: from, to (location-local x, z) of each, one after the other.
func planned_edges() -> PackedVector2Array:
	return _gaps.edge_lines if _gaps else PackedVector2Array()


func _flag(flags: PackedByteArray, x: float, z: float) -> bool:
	if flags.is_empty():
		return false
	var grid: Vector2i = Vector2i(terrain.to_grid(Vector2(x, z)).round())
	if not Rect2i(0, 0, terrain.cells + 1, terrain.cells + 1).has_point(grid):
		return false
	return flags[terrain.index(grid.x, grid.y)] == 1


## Spots (location-local x, z) a player could fall to from walkable ground without a way back to
## the ship: should be none (see `LocationTerrain.stuck_spots`).
func stuck_spots() -> PackedVector2Array:
	return terrain.stuck_spots(_reachable, MAX_WALK_SLOPE, _blocked)


func _generate_ground(rng: RandomNumberGenerator) -> void:
	var bounds: Rect2 = landing_site
	for area: LocationLayout.Area in layout.areas:
		bounds = bounds.merge(
			Rect2(area.center - Vector2.ONE * area.radius, Vector2.ONE * area.radius * 2.0)
		)
	var side: float = maxf(bounds.size.x, bounds.size.y) + (rim_width + biome.cliff_width) * 2.0
	var cells: int = ceili(side / cell)
	size = cells * cell
	terrain = LocationTerrain.new(bounds.get_center() - Vector2.ONE * size * 0.5, cells, cell)
	var wobble: FastNoiseLite = make_noise(rng, 1.0 / 30.0, 2)
	var swells: FastNoiseLite = make_noise(rng, 1.0 / biome.floor_relief_size, 3)
	var rock: FastNoiseLite = make_noise(rng, 1.0 / 90.0, 3)
	var bumps: FastNoiseLite = make_noise(rng, 1.0 / 12.0, 2)
	var outside: PackedFloat32Array = terrain.distance_outside(_carve(wobble))
	var walls := LocationWalls.new(terrain, biome, rock, view_direction)
	if not _from_areas.is_empty():
		walls.deeper.resize(outside.size())
		for i: int in outside.size():
			var farther: float = _from_areas[i] - outside[i]
			walls.deeper[i] = smoothstep(CANYON_FADE.x, CANYON_FADE.y, farther) * biome.canyon_depth
	if biome.has_gaps():
		# Only gap biomes draw these, so the other biomes' worlds stay as they were for their seeds.
		var widths: FastNoiseLite = make_noise(rng, 1.0 / 40.0, 2)
		var pits: FastNoiseLite = (
			make_noise(rng, 1.0, 1) if biome.gap_shape == LocationBiome.GapShape.PITS else null
		)
		_gaps = LocationGaps.new(terrain, biome, widths, pits)
		_widen_gaps()
	# Frozen lakes and mud pools: the slick ice or the mud.
	for pool: Vector3 in _features.fit_lakes(_lanes) + _features.fit_pools(_lanes):
		if biome.hazard in [LocationBiome.Hazard.SLICK_ICE, LocationBiome.Hazard.MUD]:
			_hazards.spots.append(pool)
		_clearings.append(Vector3(pool.x, pool.y, pool.z + 1.0))
	_clearings.append_array(_features.clearings())
	_features.collect()
	for z: int in cells + 1:
		for x: int in cells + 1:
			var at := Vector2(terrain.origin.x + x * cell, terrain.origin.y + z * cell)
			var index: int = terrain.index(x, z)
			var ground: float = _features.height(at, swells)
			if not _levels.is_empty():
				ground += _levels[index]
			var distance: float = outside[index]
			var height: float = ground
			var top: float = _features.rock_top(at)
			if _gaps:
				# Lowered into the gap, from the open ground or from the rock behind it.
				var gap: float = _gaps.share(x, z, distance) * walls.share(distance)
				var rise: float = walls.rise(x, z, outside, top) if biome.has_walls() else 0.0
				var bottom: float = -biome.gap_depth if biome.gap_fill else ground - biome.gap_depth
				height = lerpf(ground + rise, bottom, gap)
			else:
				height += walls.rise(x, z, outside, top)
			if not _bridge_lift.is_empty():
				height += _bridge_lift[index]
			height += bumps.get_noise_2dv(at) * biome.bump_height * (1.0 - _features.smoothness(at))
			var to_edge: float = minf(minf(x, cells - x), minf(z, cells - z)) * cell
			var rim: float = 1.0 - smoothstep(0.0, rim_width, to_edge)
			height += rim * rim * rim_height
			terrain.set_height(x, z, height)
	if _gaps:
		_gaps.raise_lips()
		_blocked = _gaps.blocked
	if biome.has_walls():
		_camera_side = walls.camera_side
	# One grid square more, so the ground between the grid points inside is flat too.
	terrain.flatten_rect(landing_site.grow(cell), landing_falloff, 0.0)


## Widens the gaps where they must be: beside the bridges, so they cross a gap and not the rock
## behind it, around lava islands and in pits (see `LocationFeatures.widen_gaps`).
func _widen_gaps() -> void:
	if biome.has_walls() and biome.pass_style == LocationBiome.PassStyle.BRIDGES:
		var width: float = biome.gap_width.y
		for way: LocationLayout.Pass in layout.passes:
			var ends: Array[LocationLayout.Area] = [layout.areas[way.from], layout.areas[way.to]]
			var reach: float = way.width * 0.5 * (1.0 + biome.pass_wobble) + width
			for point: Vector2 in way.points:
				var outside_ends: bool = true
				for area: LocationLayout.Area in ends:
					if point.distance_to(area.center) < area.radius:
						outside_ends = false
				if outside_ends:
					_gaps.widen(point, reach, width)
	_features.widen_gaps(_gaps)


## How open each grid point is: positive inside an area, a pass or around the landing site (how
## far inside, in m), negative outside. Also marks the lanes along the passes, and notes the levels
## (terraces) and how far the areas are (slot canyons).
func _carve(wobble: FastNoiseLite) -> PackedFloat32Array:
	var openness := PackedFloat32Array()
	openness.resize(terrain.heights.size())
	openness.fill(-INF)
	if biome.terrace_step > 0.0:
		_levels.resize(openness.size())
	passes = LocationPasses.new(terrain, biome, layout)
	passes.mark(ramp_exit, Vector2(landing_yard.x, landing_yard.y))
	_lanes = passes.lanes
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
			openness[terrain.index(x, z)] = LANDING_MARGIN - landing_distance(at)
	for area: LocationLayout.Area in layout.areas:
		# A plateau's outline only wobbles outwards, so its cliff never closes in on the mesa (from its
		# top the rock would be a small step).
		var outward: bool = area.kind == LocationLayout.Kind.PLATEAU
		# A dry wash is long and narrow, across the way it runs.
		var narrow: Vector2 = Vector2.ZERO
		if area.kind == LocationLayout.Kind.DRY_WASH:
			narrow = area.facing.orthogonal() / LocationLayout.WASH_WIDTH
		_stamp(openness, bends, area.center, area.radius, AREA_WOBBLE, outward, narrow, area.level)
	var in_areas: PackedFloat32Array = openness.duplicate()
	for way: LocationLayout.Pass in layout.passes:
		var level: float = minf(layout.areas[way.from].level, layout.areas[way.to].level)
		for at: Vector2 in way.points:
			_stamp(
				openness, bends, at, way.width * 0.5, biome.pass_wobble, false, Vector2.ZERO, level
			)
	if not _levels.is_empty():
		for way: LocationLayout.Pass in layout.passes:
			passes.lay_ramp(_levels, way, bends, in_areas)
		var known := PackedByteArray()
		known.resize(openness.size())
		for i: int in openness.size():
			known[i] = 1 if openness[i] > -INF else 0
		terrain.spread(_levels, known)
	if biome.pass_style == LocationBiome.PassStyle.SLOT_CANYONS:
		_from_areas = terrain.distance_outside(in_areas)
	if biome.pass_style == LocationBiome.PassStyle.BRIDGES:
		_bridges.resize(openness.size())
		if biome.bridge_rise > 0.0:
			_bridge_lift.resize(openness.size())
		for i: int in openness.size():
			if openness[i] > 0.0 and in_areas[i] <= 0.0:
				_bridges[i] = 1
				if biome.bridge_rise > 0.0:
					var ramp: float = smoothstep(0.0, BRIDGE_RAMP, -in_areas[i])
					_bridge_lift[i] = ramp * biome.bridge_rise
	_features.carve(openness, _lanes)
	return openness


## Raises `openness` around `center` to a round outline of `radius`, wobbling by `wobble` (a share
## of the radius) with `bends` (only outwards with `outward_only`), squeezed along `narrow` (its
## length: how many times; zero: round). Its level (terraces) is `level`; where open ground
## overlaps, the higher one's.
func _stamp(
	openness: PackedFloat32Array,
	bends: PackedFloat32Array,
	center: Vector2,
	radius: float,
	wobble: float,
	outward_only: bool = false,
	narrow: Vector2 = Vector2.ZERO,
	level: float = 0.0
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
			var offset: Vector2 = at - center
			if narrow != Vector2.ZERO:
				var along: float = narrow.dot(offset) / narrow.length_squared()
				offset += narrow * along * (narrow.length() - 1.0)
			var inside: float = radius * (1.0 + bend * wobble) - offset.length()
			if not _levels.is_empty():
				if inside > 0.0 and openness[index] > 0.0:
					# Where open ground overlaps, the higher level: a ramp's foot reaches into the lower
					# area.
					_levels[index] = maxf(_levels[index], level)
				elif inside > openness[index]:
					_levels[index] = level
			openness[index] = maxf(openness[index], inside)


## The random stream of a generator stage (`stage`: its name) for `world_seed`.
static func random_stream(seed_of_world: int, stage: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_of_world, stage])
	return rng


func _stream(stage: String) -> RandomNumberGenerator:
	return random_stream(world_seed, stage)


## Smooth noise for the generator, its seed drawn from `rng`.
static func make_noise(rng: RandomNumberGenerator, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = rng.randi()
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	return noise


## How far location-local `at` lies from the landing site, in m (0 on it).
func landing_distance(at: Vector2) -> float:
	var offset: Vector2 = (at - landing_site.get_center()).abs() - landing_site.size * 0.5
	return offset.max(Vector2.ZERO).length()


## A reachable, gentle spot off the lanes where `fits` agrees, within `spread` of `around` (tried
## at random from `rng`); `Vector3.INF` when there is none.
func find_site(
	rng: RandomNumberGenerator, radius: float, fits: Callable, around: Vector2, spread: float
) -> Vector3:
	var area: Rect2 = terrain.rect().grow(-rim_width - radius)
	for attempt: int in PLACEMENT_TRIES:
		var at: Vector2 = (
			around + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, spread)
		)
		if area.has_point(at) and fits.call(at) and _is_gentle(at, radius):
			return Vector3(at.x, 0.0, at.y)
	return Vector3.INF


## Whether the ground within `radius` of `at` is reachable, off the lanes and the hazard and even
## enough to build on, and flattening it changes no step from walkable to too steep or back.
func _is_gentle(at: Vector2, radius: float) -> bool:
	if parts.covers(at, radius) or near_hazard(at, radius + SITE_FALLOFF):
		return false
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
	return flattening_keeps_steps(at, radius)


## Whether flattening a site of `radius` at `at` (see `add_site`) leaves every step between
## neighboring grid points as it was: walkable ones walkable, too steep ones too steep (but for
## steps onto ground behind a gap's walls, which nobody walks on either way).
func flattening_keeps_steps(at: Vector2, radius: float, falloff: float = SITE_FALLOFF) -> bool:
	var level: float = terrain.height_at(at.x, at.y)
	var max_rise: float = MAX_WALK_SLOPE * cell
	var changed: Dictionary[int, float] = {}
	var around: Array[Vector2i] = _grid_within(at, radius + falloff + cell)
	if around.is_empty():
		return false
	for point: Vector2i in around:
		var index: int = terrain.index(point.x, point.y)
		var spot: Vector3 = terrain.point(point.x, point.y)
		var outside: float = Vector2(spot.x, spot.z).distance_to(at) - radius
		var weight: float = 1.0 - smoothstep(0.0, falloff, outside)
		changed[index] = lerpf(terrain.heights[index], level, weight)
	for point: Vector2i in around:
		var index: int = terrain.index(point.x, point.y)
		for next: Vector2i in terrain.neighbors(point.x, point.y):
			var other: int = terrain.index(next.x, next.y)
			if not _blocked.is_empty() and (_blocked[index] or _blocked[other]):
				continue
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


## Flattens the ground at `site` (blending back over `falloff` m) and keeps scatter away from it
## (`room` m beyond `radius`).
func add_site(site: Vector3, radius: float, room: float, falloff: float = SITE_FALLOFF) -> void:
	var at := Vector2(site.x, site.z)
	terrain.flatten(at, radius, falloff, terrain.height_at(at.x, at.y))
	_clearings.append(Vector3(site.x, site.z, radius + room))


## The ground's chunks: their mesh arrays (painted) and collision faces.
func _plan_ground() -> void:
	var rng: RandomNumberGenerator = _stream("paint")
	var shades: FastNoiseLite = make_noise(rng, 1.0 / 40.0, 2)
	var patches: FastNoiseLite = make_noise(rng, 1.0 / 18.0, 2)
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
## areas, a gap's bottom darker, its lip and the bridges, and the hazard, in their own tints), A the
## share of scree (at the foot of steep ground and in patches).
## `highest`: the highest ground around each grid point (`LocationTerrain.highest_around`).
func _ground_paint(
	point: Vector3, shades: FastNoiseLite, patches: FastNoiseLite, highest: PackedFloat32Array
) -> Color:
	var high: float = smoothstep(0.0, biome.wall_height, point.y)
	var tint: Color = biome.low_ground_tint.lerp(Color.WHITE, high)
	var at := Vector2(point.x, point.z)
	var grid := Vector2i(terrain.to_grid(at).round())
	var index: int = terrain.index(grid.x, grid.y)
	# Lips, bridges and the hazard keep their own tint, without scree, so they read from afar.
	var plain: bool = false
	if _gaps:
		# Deeper ground fades towards the gap's bottom; a band at the floor's level has its tint.
		var low: float = float(_gaps.gaps[index])
		if biome.gap_depth > 0.0:
			low = smoothstep(0.0, biome.gap_depth, -point.y)
		tint = tint.lerp(biome.gap_tint, low)
		var lip: bool = _blocked[index] and not _gaps.gaps[index]
		if lip or (not _bridges.is_empty() and _bridges[index]):
			tint = biome.lip_tint
			plain = true
	if near_hazard(at, -HAZARD_MARGIN):
		tint = biome.hazard_tint
		plain = true
	# A dry wash's bed (lighter sand) and a trail's path (packed soil), without scree.
	var bed: float = _features.bed(at)
	if bed > 0.0:
		tint = tint.lerp(LocationFeatures.BED_TINT, bed)
		plain = plain or bed > 0.5
	var path: float = passes.path_at(at)
	if path > 0.0:
		tint = tint.lerp(LocationPasses.PATH_TINT, path)
		plain = plain or path > 0.5
	tint *= 1.0 + shades.get_noise_2dv(at) * 2.0 * biome.tint_variation
	# Scree collects where the ground rises steeply close by.
	var rise: float = highest[index] - point.y
	var foot: float = smoothstep(1.5, 3.5, rise)
	var patch: float = smoothstep(0.3, 0.5, patches.get_noise_2dv(at))
	patch *= smoothstep(5.0, 20.0, landing_distance(at))
	tint.a = 0.0 if plain else clampf((foot + patch) * biome.scree * 2.0, 0.0, 1.0)
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


## Whether a plant or rock of `radius` (0: not blocking) may grow at location-local `at`: on the
## ground, off the landing site, the gaps (or only on them, `on_barrier`: a band of growth), the
## clearings, the trails' paths and (blocking ones) the lanes, and not `tall` on the rock on the
## camera's side (see `LocationScatter`).
func lets_grow(at: Vector2, radius: float, tall: bool, on_barrier: bool = false) -> bool:
	if not terrain.rect().grow(-cell).has_point(at):
		return false
	if landing_distance(at) < 4.0 + radius:
		return false
	var grid: Vector2i = Vector2i(terrain.to_grid(at).round())
	var index: int = terrain.index(grid.x, grid.y)
	var barrier: bool = not _blocked.is_empty() and _blocked[index] == 1
	if (
		(radius > 0.0 and _lanes[index] == 1)
		or (tall and not _camera_side.is_empty() and _camera_side[index] == 1)
		or barrier != on_barrier
		or passes.path_at(at) > 0.3
	):
		return false
	for clearing: Vector3 in _clearings:
		if at.distance_to(Vector2(clearing.x, clearing.y)) < clearing.z + radius:
			return false
	return true


## Adds the ore nodes; returns the late deposit's, not in the tree.
func _add_ore_nodes() -> Array[OreNode]:
	var ore_nodes := Node3D.new()
	ore_nodes.name = "OreNodes"
	add_child(ore_nodes)
	var turns: RandomNumberGenerator = _stream("ore_turns")
	var late: Array[OreNode] = []
	for i: int in sites.ores.size():
		var node := ORE_NODE.instantiate() as OreNode
		node.name = "Ore%d" % (i + 1)
		node.ore_type = sites.ores[i].ore
		node.rich = sites.ores[i].rich
		node.variant = i
		node.position = sites.ores[i].position
		node.rotation.y = turns.randf() * TAU
		if sites.ores[i].late:
			late.append(node)
		else:
			ore_nodes.add_child(node)
	return late


func _add_nests() -> void:
	var nests := Node3D.new()
	nests.name = "AlienNests"
	add_child(nests)
	var table: HatchTable = null
	for i: int in sites.nests.size():
		var quest: QuestVisit.Entry = sites.nests[i].quest
		var nest := (QUEST_NEST if quest else ALIEN_NEST).instantiate() as AlienNest
		table = _hatch_table(nest.hive)
		nest.table = table
		nest.name = "Nest%d" % (i + 1)
		nest.position = sites.nests[i].position
		if quest:
			nest.destroyed.connect(quest_visit.count.bind(quest, 1.0))
		nests.add_child(nest)
	if table:
		_add_apex(table)


## What the crates hold, in the order they're placed (null: a supply cache): the quest visit's
## fragments, one per crate, spread over them from a stream of their own (as many as there are
## crates; the rest wait for a later visit).
func _crate_contents() -> Array[CrateContent]:
	var contents: Array[CrateContent] = []
	for part: LocationParts.Placed in parts.placed:
		for i: int in part.markers(PartMarker.Kind.CRATE).size():
			contents.append(null)
	var wanted: Array[QuestVisit.Entry] = []
	if quest_visit:
		wanted = quest_visit.fragment_entries()
	var crates: Array[int] = []
	crates.assign(range(contents.size()))
	var rng: RandomNumberGenerator = _stream("fragments")
	for i: int in range(crates.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = crates[i]
		crates[i] = crates[j]
		crates[j] = swap
	for i: int in mini(wanted.size(), crates.size()):
		var fragment := BlueprintFragment.new()
		fragment.entry = wanted[i]
		contents[crates[i]] = fragment
	return contents


## What every quest site's part holds at its quest anchor (its middle without one): a hunt's brood
## nest or its strain asleep in a lair, an item to recover (`QuestItem`), else (if it isn't only
## there for its crate) a `QuestSite` that counts for its goal when reached.
func _add_quest_sites() -> void:
	if not quest_visit:
		return
	for entry: QuestVisit.Entry in quest_visit.entries:
		var part: LocationParts.Placed = parts.placed_for(entry.site)
		if not part:
			continue
		var anchors: Array[Vector3] = part.markers(PartMarker.Kind.QUEST_ANCHOR)
		var at: Vector3 = anchors[0] if not anchors.is_empty() else part.origin
		if entry.hunted and entry.brood:
			_add_brood_nest(entry, at)
		elif entry.hunted:
			_add_lair(entry, at)
		elif entry.item:
			var item := QuestItem.new()
			item.name = "QuestItem"
			item.entry = entry
			item.position = at
			add_child(item, true)
		elif entry.fragments == 0:
			var site := QuestSite.new()
			site.name = "QuestSite"
			site.position = at
			site.reached.connect(quest_visit.count.bind(entry, 1.0).unbind(1))
			add_child(site, true)


## `entry`'s brood nest at `at`: it hatches the hunted strain, as many as the hunt still needs;
## kills of it and the nest destroyed count for the hunt.
func _add_brood_nest(entry: QuestVisit.Entry, at: Vector3) -> void:
	var nest := entry.brood.instantiate() as AlienNest
	nest.name = "BroodNest"
	nest.table = _hatch_table(nest.hive)
	nest.brood = entry.hunted
	nest.brood_left = quest_visit.kills_left(entry)
	nest.position = at
	nest.rotation.y = _stream("brood_nest").randf() * TAU
	nest.hatched.connect(
		func(alien: Alien) -> void:
			if alien.strain == entry.hunted:
				alien.died.connect(quest_visit.count_kill.bind(entry))
	)
	nest.destroyed.connect(quest_visit.count_brood.bind(entry))
	(get_node(^"AlienNests") as Node3D).add_child(nest)


## The hunted strain (the Ravager) asleep at `at`, in its lair, until a player comes close: killing
## it counts for the hunt.
func _add_lair(entry: QuestVisit.Entry, at: Vector3) -> void:
	var table: HatchTable = _hatch_table(HIVE)
	var lair := ApexLair.new()
	lair.name = "Lair"
	lair.strain = entry.hunted
	lair.health_factor = table.health_factor
	lair.damage_factor = table.damage_factor
	lair.route = [at] as Array[Vector3]
	lair.asleep = true
	# The apex appears when the location enters the tree.
	var count: Callable = quest_visit.count_kill.bind(entry)
	lair.ready.connect(func() -> void: lair.apex.died.connect(count), CONNECT_ONE_SHOT)
	add_child(lair, true)


## What the nests hatch here (made once, from `hive`).
func _hatch_table(hive: AlienHive) -> HatchTable:
	if not _table:
		_table = hive.table(alien_tier, biome, preview_strain, world_seed)
	return _table


## The late deposit at its part (its time drawn from a stream of its own), with its ore `nodes`;
## none when its part found no room.
func _add_late_deposit(nodes: Array[OreNode]) -> void:
	var part: LocationParts.Placed = parts.late_part()
	if not part:
		for node: OreNode in nodes:
			node.free()
		return
	var deposit := LateDeposit.new()
	deposit.name = "LateDeposit"
	deposit.part = part.node
	deposit.ore_nodes = nodes
	deposit.ore_holder = get_node(^"OreNodes") as Node3D
	deposit.at = _stream("late_deposit").randf_range(LateDeposit.TIMES.x, LateDeposit.TIMES.y)
	deposit.position = part.origin
	add_child(deposit)


## The hive's apex on some locations (see `AlienHive.apex_chance_at`, picked by the seed): it roams
## between the middles of the areas away from the landing site, starting in one of them.
func _add_apex(table: HatchTable) -> void:
	var hive: AlienHive = table.hive
	var rng: RandomNumberGenerator = _stream("apex")
	if rng.randf() >= hive.apex_chance_at(alien_tier):
		return
	if quest_visit and quest_visit.has_lair(hive.apex):
		return
	var route: Array[Vector3] = []
	for area: LocationLayout.Area in layout.areas:
		var at: Vector2 = area.center
		if (
			area.kind != LocationLayout.Kind.LANDING
			and landing_distance(at) >= APEX_LANDING_DISTANCE
			and is_reachable(at.x, at.y)
		):
			route.append(Vector3(at.x, terrain.height_at(at.x, at.y), at.y))
	if route.is_empty():
		return
	var lair := ApexLair.new()
	lair.name = "Apex"
	lair.strain = hive.apex
	lair.health_factor = table.health_factor
	lair.damage_factor = table.damage_factor
	lair.route = route
	lair.start = rng.randi() % route.size()
	add_child(lair)
