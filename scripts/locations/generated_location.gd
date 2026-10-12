class_name GeneratedLocation
extends Node3D
## An outside world generated from a seed and a biome when it appears (every run gets a fresh
## one): rolling hills, terraced in places into plateaus with cliffs between them, a mountain rim
## at the edges, plants and rocks, ore fields and alien nests. The ship stands at the location's
## origin, on a flat landing site; the location's axes are the ship's (nose to -x, ramp to +x).
## Ores and nests only lie where players can walk to from the ship; rarer ores lie farther away.
## Everything the generator places is greybox; the values are TBD (playtest).

const ORE_NODE: PackedScene = preload("res://scenes/mining/ore_node.tscn")
const ALIEN_NEST: PackedScene = preload("res://scenes/aliens/alien_nest.tscn")
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

## The kind of place; when not set, one of `biomes` is picked by the seed.
@export var biome: LocationBiome
@export var biomes: Array[LocationBiome] = []
## Same seed and biome, same world; 0: a new one every time.
@export var world_seed: int = 0
## Edge length of the square world, in m.
@export var size: float = 500.0
## Distance between the ground's grid points, in m.
@export var cell: float = 2.0
## How far the landing site lies from the world's center at most, in m.
@export var landing_offset: float = 100.0
## Location-local area kept flat at height 0 for the ship, its ramp and the space in front of it.
@export var landing_site: Rect2 = Rect2(-96.0, -26.0, 146.0, 52.0)
## Where players step off the ramp, location-local x, z.
@export var ramp_exit: Vector2 = Vector2(20.0, 0.0)
## How far from the ramp exit the first two ore fields lie (min, max), in m: found right away.
@export var near_ore_distance: Vector2 = Vector2(25.0, 55.0)
## Distance over which the ground around the landing site blends back to the hills, in m.
@export var landing_falloff: float = 30.0
## Width of the mountain rim at the edges, in m.
@export var rim_width: float = 40.0
@export var rim_height: float = 24.0
## Closest an ore field is to another one, in m.
@export var ore_field_spacing: float = 40.0
## Closest two nests are to each other, in m.
@export var nest_spacing: float = 60.0
## Baked for the aliens once the world is generated (none without it).
@export var navigation_mesh: NavigationMesh

## The generated ground.
var terrain: LocationTerrain

var _rng := RandomNumberGenerator.new()
## Grid points players can walk to from the ship (1 = reachable).
var _reachable: PackedByteArray
## Places scatter keeps away from (x, z, radius), location-local.
var _clearings: Array[Vector3] = []
## Location-local positions of the ore nodes, and of the nests, to be placed.
var _ore_sites: Array[Vector3] = []
var _ore_site_types: Array[OreType] = []
var _nest_sites: Array[Vector3] = []


func _ready() -> void:
	while world_seed == 0:
		world_seed = randi()
	_rng.seed = world_seed
	if not biome:
		biome = biomes[_rng.randi() % biomes.size()]
	_generate_ground()
	_reachable = terrain.reachable_from(ramp_exit, MAX_WALK_SLOPE)
	_pick_ore_sites()
	_pick_nest_sites()
	_add_ground()
	_add_bounds()
	_add_scatter()
	_add_ore_nodes()
	_add_nests()
	if navigation_mesh:
		var navigation := LocationNavigation.new()
		navigation.name = "Navigation"
		navigation.navigation_mesh = navigation_mesh
		add_child(navigation)


## Whether players can walk from the ship to location-local `x`, `z`.
func is_reachable(x: float, z: float) -> bool:
	var grid: Vector2i = Vector2i(terrain.to_grid(Vector2(x, z)).round())
	if not Rect2i(0, 0, terrain.cells + 1, terrain.cells + 1).has_point(grid):
		return false
	return _reachable[terrain.index(grid.x, grid.y)] == 1


func _generate_ground() -> void:
	var cells: int = roundi(size / cell)
	var center := Vector2(
		_rng.randf_range(-landing_offset, landing_offset),
		_rng.randf_range(-landing_offset, landing_offset)
	)
	terrain = LocationTerrain.new(center - Vector2.ONE * size * 0.5, cells, cell)
	var hills: FastNoiseLite = _noise(1.0 / biome.hill_size, 4)
	var cliffs: FastNoiseLite = _noise(1.0 / (biome.hill_size * 1.5), 2)
	var bumps: FastNoiseLite = _noise(1.0 / 12.0, 2)
	# Noise is about -0.5 to 0.5 most of the time; terraced where it's above the threshold.
	var cliff_threshold: float = lerpf(0.4, -0.4, biome.cliff_share)
	var landing_center: Vector2 = landing_site.get_center()
	var level: float = hills.get_noise_2dv(landing_center) * biome.hill_height
	for z: int in cells + 1:
		for x: int in cells + 1:
			var at := Vector2(terrain.origin.x + x * cell, terrain.origin.y + z * cell)
			var height: float = hills.get_noise_2dv(at) * biome.hill_height - level
			# Smooth near the landing site, so there's always a way out.
			var calm: float = smoothstep(
				landing_falloff, landing_falloff + 60.0, _distance_to_landing_site(at)
			)
			var terraced: float = smoothstep(
				cliff_threshold - 0.08, cliff_threshold + 0.08, cliffs.get_noise_2dv(at)
			)
			height = lerpf(height, _terrace(height), terraced * calm)
			height += bumps.get_noise_2dv(at) * biome.bump_height
			var to_edge: float = minf(minf(x, cells - x), minf(z, cells - z)) * cell
			var rim: float = 1.0 - smoothstep(0.0, rim_width, to_edge)
			height += rim * rim * rim_height
			terrain.set_height(x, z, height)
	terrain.flatten_rect(landing_site, landing_falloff, 0.0)


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


## Ore fields: a few nodes of one type close together. The first two are close to the ramp.
func _pick_ore_sites() -> void:
	if biome.ores.is_empty():
		return
	var farthest: float = size * 0.75
	var fields: Array[Vector3] = []
	for field: int in biome.ore_fields:
		var near: bool = field < 2
		var center: Vector3 = _find_site(
			ORE_SITE_RADIUS,
			func(at: Vector2) -> bool:
				if near:
					var to_ramp: float = at.distance_to(ramp_exit)
					if to_ramp < near_ore_distance.x or to_ramp > near_ore_distance.y:
						return false
				return (
					_distance_to_landing_site(at) >= 10.0
					and _far_from(at, fields, ore_field_spacing)
				)
		)
		if center == Vector3.INF:
			continue
		fields.append(center)
		var distance: float = Vector2(center.x, center.z).length()
		var rank: float = distance / farthest * biome.ores.size() + _rng.randf_range(-0.6, 0.6)
		var ore_type: OreType = biome.ores[clampi(int(rank), 0, biome.ores.size() - 1)]
		if near:
			ore_type = biome.ores[0]
		var count: int = _rng.randi_range(biome.ore_nodes_per_field.x, biome.ore_nodes_per_field.y)
		for node: int in count:
			var site: Vector3 = Vector3(center.x, 0.0, center.z)
			if node > 0:
				site = _find_site(
					ORE_SITE_RADIUS,
					func(at: Vector2) -> bool:
						var to_center: float = at.distance_to(Vector2(center.x, center.z))
						return (
							to_center < 12.0
							and _distance_to_landing_site(at) >= 10.0
							and _far_from(at, _ore_sites, 7.0)
						),
					Vector2(center.x, center.z),
					12.0
				)
			if site == Vector3.INF:
				continue
			_add_site(site, ORE_SITE_RADIUS)
			_ore_sites.append(Vector3(site.x, terrain.height_at(site.x, site.z), site.z))
			_ore_site_types.append(ore_type)


func _pick_nest_sites() -> void:
	for nest: int in biome.nests:
		var site: Vector3 = _find_site(
			NEST_SITE_RADIUS,
			func(at: Vector2) -> bool:
				return (
					_distance_to_landing_site(at) >= biome.nest_min_distance
					and _far_from(at, _nest_sites, nest_spacing)
					and _far_from(at, _ore_sites, 20.0)
				)
		)
		if site == Vector3.INF:
			continue
		_add_site(site, NEST_SITE_RADIUS + 2.0)
		_nest_sites.append(Vector3(site.x, terrain.height_at(site.x, site.z), site.z))


## A reachable, gentle spot where `fits` agrees, within `spread` of `around` (or anywhere inside
## the rim); `Vector3.INF` when there is none.
func _find_site(
	radius: float, fits: Callable, around: Vector2 = Vector2.INF, spread: float = 0.0
) -> Vector3:
	var area: Rect2 = terrain.rect().grow(-rim_width - radius)
	for attempt: int in PLACEMENT_TRIES:
		var at: Vector2
		if around == Vector2.INF:
			at = Vector2(
				_rng.randf_range(area.position.x, area.end.x),
				_rng.randf_range(area.position.y, area.end.y)
			)
		else:
			at = around + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, spread)
		if area.has_point(at) and fits.call(at) and _is_gentle(at, radius):
			return Vector3(at.x, 0.0, at.y)
	return Vector3.INF


## Whether the ground within `radius` of `at` is reachable and even enough to build on.
func _is_gentle(at: Vector2, radius: float) -> bool:
	var low: Vector2 = terrain.to_grid(at - Vector2.ONE * radius).floor()
	var high: Vector2 = terrain.to_grid(at + Vector2.ONE * radius).ceil()
	var lowest: float = INF
	var highest: float = -INF
	for z: int in range(int(low.y), int(high.y) + 1):
		for x: int in range(int(low.x), int(high.x) + 1):
			if x < 0 or z < 0 or x > terrain.cells or z > terrain.cells:
				return false
			if not _reachable[terrain.index(x, z)]:
				return false
			lowest = minf(lowest, terrain.get_height(x, z))
			highest = maxf(highest, terrain.get_height(x, z))
	return highest - lowest <= MAX_SITE_RISE * radius * 2.0


func _far_from(at: Vector2, sites: Array[Vector3], distance: float) -> bool:
	for site: Vector3 in sites:
		if at.distance_to(Vector2(site.x, site.z)) < distance:
			return false
	return true


## Flattens the ground at `site` and keeps scatter away from it.
func _add_site(site: Vector3, radius: float) -> void:
	var at := Vector2(site.x, site.z)
	terrain.flatten(at, radius, 3.0, terrain.height_at(at.x, at.y))
	_clearings.append(Vector3(site.x, site.z, radius + 1.5))


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
			var body := StaticBody3D.new()
			body.name = "Chunk%d_%d" % [chunk_x, chunk_z]
			var mesh := MeshInstance3D.new()
			mesh.mesh = terrain.build_mesh(from, to, paint)
			mesh.material_override = material
			body.add_child(mesh)
			var shape := CollisionShape3D.new()
			shape.shape = terrain.build_shape(from, to)
			body.add_child(shape)
			ground.add_child(body)


## Vertex color of the ground at `point`: RGB a tint (lighter on the high ground, varying over
## large areas), A the share of scree (at the foot of steep ground and in patches).
## `highest`: the highest ground around each grid point (`LocationTerrain.highest_around`).
func _ground_paint(
	point: Vector3, shades: FastNoiseLite, patches: FastNoiseLite, highest: PackedFloat32Array
) -> Color:
	var high: float = smoothstep(0.0, biome.hill_height * 0.5, point.y)
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
	var chunk_size: float = CHUNK_CELLS * cell
	var blockers: Array[Vector3] = []
	for type: ScatterType in biome.scatter:
		var by_chunk: Dictionary[Vector2i, Array] = {}
		for placed: Transform3D in _scatter_transforms(type, blockers):
			var chunk: Vector2i = Vector2i(
				((Vector2(placed.origin.x, placed.origin.z) - terrain.origin) / chunk_size).floor()
			)
			if not by_chunk.has(chunk):
				by_chunk[chunk] = []
			by_chunk[chunk].append(placed)
		for chunk: Vector2i in by_chunk:
			_add_scatter_chunk(scatter, type, chunk, by_chunk[chunk])


## Where `type` grows: on a jittered grid, thinned out by patches, steep ground and clearings.
## Blocking ones keep their distance from each other (`blockers`: x, z, radius).
func _scatter_transforms(type: ScatterType, blockers: Array[Vector3]) -> Array[Transform3D]:
	var placed: Array[Transform3D] = []
	if type.density <= 0.0 or not type.get_mesh():
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
	if terrain.slope(grid.x, grid.y) > max_slope:
		return false
	for clearing: Vector3 in _clearings:
		if at.distance_to(Vector2(clearing.x, clearing.y)) < clearing.z + radius:
			return false
	if radius > 0.0:
		for blocker: Vector3 in blockers:
			if at.distance_squared_to(Vector2(blocker.x, blocker.y)) < pow(blocker.z + radius, 2):
				return false
	return true


func _add_scatter_chunk(
	parent: Node3D, type: ScatterType, chunk: Vector2i, transforms: Array
) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = type.get_mesh()
	multimesh.instance_count = transforms.size()
	for i: int in transforms.size():
		var placed: Transform3D = transforms[i]
		multimesh.set_instance_transform(i, placed)
	var instance := MultiMeshInstance3D.new()
	instance.name = "%s%d_%d" % [type.display_name.to_pascal_case(), chunk.x, chunk.y]
	instance.multimesh = multimesh
	instance.visibility_range_end = type.visibility_range
	# Fade in and out instead of popping, a whole chunk at a time.
	instance.visibility_range_end_margin = type.visibility_range * 0.25
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not type.cast_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	if type.blocking_radius <= 0.0:
		return
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
