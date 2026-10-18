extends GutTest

const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
const TEST_MAP: PackedScene = preload("res://game/maps/main.tscn")
const REAL_TIME := preload("res://tests/support/real_time.gd")
const SWEEP := preload("res://tests/support/location_sweep.gd")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")
const OVERGROWTH: LocationBiome = preload("res://game/locations/biomes/overgrowth.tres")
const FROST: LocationBiome = preload("res://game/locations/biomes/frost.tres")
const ASH: LocationBiome = preload("res://game/locations/biomes/ash.tres")
const AREAS: int = 6


## A smaller world than in the game, so the tests stay quick.
func _generate(
	world_seed: int, biome: LocationBiome = DUST, nest_factor: float = 1.0
) -> GeneratedLocation:
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = world_seed
	location.biome = biome
	location.nest_factor = nest_factor
	location.area_count = AREAS
	add_child_autofree(location)
	return location


func test_same_seed_same_world() -> void:
	var first: GeneratedLocation = _generate(7)
	var second: GeneratedLocation = _generate(7)
	assert_eq(first.terrain.heights, second.terrain.heights)
	assert_eq(_positions(first, "OreNodes"), _positions(second, "OreNodes"))
	assert_eq(_positions(first, "AlienNests"), _positions(second, "AlienNests"))
	var other: GeneratedLocation = _generate(8)
	assert_ne(first.terrain.heights, other.terrain.heights)


func test_without_seed_every_world_is_new() -> void:
	var first: GeneratedLocation = _generate(0)
	var second: GeneratedLocation = _generate(0)
	assert_ne(first.world_seed, 0)
	assert_ne(first.world_seed, second.world_seed)


func test_picks_a_biome_when_none_is_set() -> void:
	var location := LOCATION.instantiate() as GeneratedLocation
	location.area_count = AREAS
	add_child_autofree(location)
	assert_has([DUST, OVERGROWTH], location.biome)


## The ship stands at the origin on flat ground at height 0, with room in front of the ramp.
func test_landing_site_is_flat() -> void:
	for biome: LocationBiome in SWEEP.BIOMES:
		var location: GeneratedLocation = _generate(3, biome)
		var site: Rect2 = location.landing_site
		for x: float in range(int(site.position.x), int(site.end.x), 4):
			for z: float in range(int(site.position.y), int(site.end.y), 4):
				assert_almost_eq(location.terrain.height_at(x, z), 0.0, 0.001)


func test_world_has_hills_and_cliffs() -> void:
	var location: GeneratedLocation = _generate(11)
	var terrain: LocationTerrain = location.terrain
	var steep: int = 0
	for z: int in range(0, terrain.cells, 2):
		for x: int in range(0, terrain.cells, 2):
			if terrain.slope(x, z) > GeneratedLocation.MAX_WALK_SLOPE:
				steep += 1
	assert_gt(steep, 0, "no cliffs")
	var lowest: float = INF
	var highest: float = -INF
	var inner: Rect2 = terrain.rect().grow(-location.rim_width)
	for z: int in terrain.cells + 1:
		for x: int in terrain.cells + 1:
			var at: Vector3 = terrain.point(x, z)
			if inner.has_point(Vector2(at.x, at.z)):
				lowest = minf(lowest, at.y)
				highest = maxf(highest, at.y)
	assert_gt(highest - lowest, 5.0, "too flat")


## Ores and nests stand on the ground, where players can walk to from the ship.
func test_ores_and_nests_are_reachable_and_on_the_ground() -> void:
	for world_seed: int in [1, 2, 3]:
		var location: GeneratedLocation = _generate(world_seed)
		var sites: Array[Node] = (
			location.get_node("OreNodes").get_children()
			+ location.get_node("AlienNests").get_children()
		)
		for site: Node3D in sites:
			assert_true(location.is_reachable(site.position.x, site.position.z), site.name)
			assert_almost_eq(
				site.position.y,
				location.terrain.height_at(site.position.x, site.position.z),
				0.01,
				site.name
			)


func test_has_ore_fields_and_nests() -> void:
	var location: GeneratedLocation = _generate(5)
	var fields: float = location.layout.areas.size() * location.biome.ore_fields_per_area
	assert_gt(location.get_node("OreNodes").get_child_count(), fields / 2.0)
	assert_gt(location.get_node("AlienNests").get_child_count(), 0)


## The first ore fields are close to the ramp and of the most common ore; nests keep away.
func test_nest_factor_scales_the_nests() -> void:
	var few: GeneratedLocation = _generate(5, DUST, 0.3)
	var normal: GeneratedLocation = _generate(5)
	var nests: int = few.get_node("AlienNests").get_child_count()
	assert_gt(nests, 0)
	assert_lte(nests, roundi(few.layout.areas.size() * DUST.nests_per_area * 0.3))
	assert_gt(normal.get_node("AlienNests").get_child_count(), nests)


func test_common_ore_close_to_ship_and_nests_far() -> void:
	for world_seed: int in [1, 2, 3]:
		var location: GeneratedLocation = _generate(world_seed)
		var close: int = 0
		for node: OreNode in location.get_node("OreNodes").get_children():
			if node.ore_type == location.biome.ores[0]:
				var to_ramp: float = Vector2(node.position.x, node.position.z).distance_to(
					location.ramp_exit
				)
				if to_ramp < location.near_ore_distance.y + 12.0:
					close += 1
		assert_gt(close, 1, "seed %d" % world_seed)
		for nest: Node3D in location.get_node("AlienNests").get_children():
			assert_gte(
				_to_landing_site(location, nest.position),
				location.biome.nest_min_distance * GeneratedLocation.NEST_STRAIGHT_SHARE
			)


## Plants and rocks grow, but not on the landing site; blocking ones have colliders.
func test_scatter_keeps_landing_site_free() -> void:
	var location: GeneratedLocation = _generate(4, OVERGROWTH)
	var instances: int = 0
	var colliders: int = 0
	for child: Node in location.get_node("Scatter").get_children():
		if child is MultiMeshInstance3D:
			instances += (child as MultiMeshInstance3D).multimesh.instance_count
		elif child is StaticBody3D:
			for shape: CollisionShape3D in child.get_children():
				colliders += 1
				var at := Vector2(shape.position.x, shape.position.z)
				assert_false(location.landing_site.has_point(at), str(at))
	assert_gt(instances, 1000)
	assert_gt(colliders, 0)


## The ground's collision matches `height_at`, which places everything.
## The ground is drawn with the biome's material; scree lies at the foot of cliffs, not on the
## landing site.
func test_ground_material_and_scree() -> void:
	var location: GeneratedLocation = _generate(11)
	var terrain: LocationTerrain = location.terrain
	var highest: PackedFloat32Array = terrain.highest_around(GeneratedLocation.SCREE_REACH)
	var at_foot: int = 0
	var scree_at_foot: int = 0
	for chunk: Node in location.get_node("Ground").get_children():
		var mesh: MeshInstance3D = chunk.get_child(0) as MeshInstance3D
		assert_eq(mesh.material_override, DUST.ground_material)
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i: int in vertices.size():
			var at: Vector3 = vertices[i]
			if location.landing_site.has_point(Vector2(at.x, at.z)):
				assert_eq(colors[i].a, 0.0, "scree on the landing site")
				continue
			var grid := Vector2i(terrain.to_grid(Vector2(at.x, at.z)).round())
			if highest[terrain.index(grid.x, grid.y)] - at.y > 4.0:
				at_foot += 1
				if colors[i].a > 0.5:
					scree_at_foot += 1
	assert_gt(at_foot, 0, "no cliffs")
	assert_eq(scree_at_foot, at_foot, "foot of a cliff without scree")


func test_collision_matches_heights() -> void:
	var location: GeneratedLocation = _generate(6)
	await wait_physics_frames(2)
	var space: PhysicsDirectSpaceState3D = location.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var area: Rect2 = location.terrain.rect().grow(-location.rim_width)
	var ground_layers: int = 0
	for chunk: CollisionObject3D in location.get_node("Ground").get_children():
		ground_layers |= chunk.collision_layer
	for i: int in 20:
		var x: float = rng.randf_range(area.position.x, area.end.x)
		var z: float = rng.randf_range(area.position.y, area.end.y)
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(x, 200.0, z), Vector3(x, -200.0, z), ground_layers
		)
		query.exclude = _scatter_bodies(location)
		var hit: Dictionary = space.intersect_ray(query)
		assert_false(hit.is_empty(), "no ground at %s" % Vector2(x, z))
		if not hit.is_empty():
			var point: Vector3 = hit[&"position"]
			assert_almost_eq(point.y, location.terrain.height_at(x, z), 0.05)


## Aliens find a way from their nests to the ship.
## Walls along the gaps' edges stop players and aliens but not shots; the slick ice is there.
func test_gap_edges_block_walking_not_shots() -> void:
	var location: GeneratedLocation = _generate(2, FROST)
	await wait_physics_frames(2)
	var edges := location.get_node("GapEdges") as StaticBody3D
	assert_eq(edges.collision_layer, PhysicsLayers.WALKING_ONLY)
	assert_eq(edges.collision_mask, 0)
	var lines: PackedVector2Array = location.planned_edges()
	var space: PhysicsDirectSpaceState3D = location.get_world_3d().direct_space_state
	for i: int in range(0, lines.size(), 2 * 97):
		var middle: Vector2 = (lines[i] + lines[i + 1]) * 0.5
		var across: Vector2 = (lines[i + 1] - lines[i]).orthogonal().normalized()
		var height: float = location.terrain.height_at(middle.x, middle.y) + 1.5
		var from: Vector3 = location.to_global(Vector3(middle.x, height, middle.y))
		var to: Vector3 = from + location.global_basis * Vector3(across.x, 0.0, across.y)
		from -= to - from
		var walking := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WALKING_ONLY)
		var stopped: Object = space.intersect_ray(walking).get(&"collider")
		assert_eq(stopped, edges, "walls stop walking")
		var shot := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.SHOTS)
		var hit: Object = space.intersect_ray(shot).get(&"collider")
		assert_ne(hit, edges, "shots fly over")
	var zones: Array[Node] = location.get_node("Hazards").get_children()
	assert_eq(zones.size(), location.planned_hazards().size())
	for zone: Node in zones:
		assert_eq((zone as GroundHazard).grip, FROST.hazard_grip)


## A built Ash fields location: lava fills its gaps, vents stand in its vent fields.
func test_lava_and_vents() -> void:
	var location: GeneratedLocation = null
	for world_seed: int in range(1, 6):
		var candidate: GeneratedLocation = _generate(world_seed, ASH)
		if not candidate.planned_hazards().is_empty():
			location = candidate
			break
	assert_not_null(location, "a seed with a vent field")
	var fill := location.get_node("GapFill") as MeshInstance3D
	assert_eq(fill.material_override, ASH.gap_fill)
	# Level, over the gaps only.
	var surface: PackedVector3Array = fill.mesh.get_faces()
	assert_gt(surface.size(), 100)
	var height: float = -ASH.gap_depth + ASH.gap_fill_level
	for i: int in range(0, surface.size(), 97):
		var at: Vector3 = surface[i]
		assert_almost_eq(at.y, height, 0.001)
		assert_false(location.is_reachable(at.x, at.z), "over walkable ground at %s" % at)
	var vents: Array[Node] = location.get_node("Hazards").get_children()
	assert_eq(vents.size(), location.planned_hazards().size())
	for vent: Node in vents:
		assert_is(vent, GroundVent)
		assert_eq((vent as GroundVent).damage, ASH.hazard_damage)


func test_navigation_reaches_nests() -> void:
	await _check_navigation(_generate(2))


## Aliens walk around the gaps to the next bridge (a test of its own: locations in one test share
## the navigation map).
func test_navigation_goes_around_gaps() -> void:
	await _check_navigation(_generate(2, FROST))


func _check_navigation(location: GeneratedLocation) -> void:
	var map: RID = location.get_world_3d().navigation_map
	var navigation := location.get_node("Navigation") as LocationNavigation
	# The walkable area is baked on a worker thread; the map takes it over at its next sync (and
	# can't be queried before its first one).
	var outside := Vector3(55.0, 0.0, 0.0)
	var walkable: bool = await REAL_TIME.wait_until(
		func() -> bool:
			return (
				navigation.is_baked()
				and NavigationServer3D.map_get_iteration_id(map) > 0
				and NavigationServer3D.map_get_closest_point(map, outside) != Vector3.ZERO
			),
		60.0
	)
	assert_true(walkable, "baked and on the map in time")
	var start: Vector3 = NavigationServer3D.map_get_closest_point(map, outside)
	for nest: Node3D in location.get_node("AlienNests").get_children():
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			map, start, nest.global_position, true
		)
		assert_gt(path.size(), 1, nest.name)
		if path.size() > 1:
			assert_lt(path[path.size() - 1].distance_to(nest.global_position), 9.0, nest.name)
		# Around the gaps, never through them.
		for point: Vector3 in path:
			var local: Vector3 = location.to_local(point)
			assert_false(location.is_gap(local.x, local.z), "%s: through a gap" % nest.name)


## The game's map lands the ship on the generated world's landing site.
func test_test_map_lands_ship_on_generated_world() -> void:
	var map := TEST_MAP.instantiate() as Node3D
	add_child_autofree(map)
	var mission := map.get_node("Mission") as Mission
	assert_true(mission.select(mission.offers[0]))
	mission.skip_flight()
	var location := map.get_node("Location") as GeneratedLocation
	var ship := map.get_node("Ship") as Ship
	assert_not_null(location)
	var length: float = mission.offers[0].length
	assert_eq(location.area_count, roundi(mission.settings.location_areas * length))
	# The camera's view, in the location's axes: down and to the side.
	var rig := map.get_node("IsoCameraRig") as IsoCameraRig
	var view: Vector3 = location.global_basis * location.view_direction
	assert_almost_eq(view, rig.view_direction(), Vector3.ONE * 0.001)
	assert_almost_eq(
		location.global_transform.origin, ship.global_transform.origin, Vector3.ONE * 0.001
	)
	assert_almost_eq(
		location.global_basis.x.dot(ship.global_basis.x), 1.0, 0.001, "same axes as the ship"
	)


## Planning on a worker thread and building afterwards makes the same world as generating it when
## it enters the tree.
func test_planned_in_the_background_same_world() -> void:
	var direct: GeneratedLocation = _generate(5)
	var planned := LOCATION.instantiate() as GeneratedLocation
	planned.world_seed = 5
	planned.biome = DUST
	planned.area_count = AREAS
	var task: int = WorkerThreadPool.add_task(planned.plan)
	WorkerThreadPool.wait_for_task_completion(task)
	assert_false(planned.is_built())
	assert_eq(planned.get_child_count(), 0, "no nodes while planning")
	planned.build()
	assert_true(planned.is_built())
	add_child_autofree(planned)
	assert_eq(planned.terrain.heights, direct.terrain.heights)
	assert_eq(_positions(planned, "OreNodes"), _positions(direct, "OreNodes"))
	assert_eq(_positions(planned, "AlienNests"), _positions(direct, "AlienNests"))
	assert_eq(
		planned.get_node("Scatter").get_child_count(), direct.get_node("Scatter").get_child_count()
	)
	assert_eq(
		planned.get_node("Ground").get_child_count(), direct.get_node("Ground").get_child_count()
	)


## Plants and rocks that block, ore nodes and nests keep a lane free along every pass.
func test_lanes_stay_free() -> void:
	var location: GeneratedLocation = _generate(4, OVERGROWTH)
	var blockers: int = 0
	for child: Node in location.get_node("Scatter").get_children():
		if child is StaticBody3D:
			for shape: CollisionShape3D in child.get_children():
				blockers += 1
				var at: Vector3 = shape.position
				assert_false(location.is_on_lane(at.x, at.z), str(at))
	assert_gt(blockers, 0)
	var sites: Array[Node] = (
		location.get_node("OreNodes").get_children()
		+ location.get_node("AlienNests").get_children()
	)
	for site: Node3D in sites:
		assert_false(location.is_on_lane(site.position.x, site.position.z), site.name)


func _positions(location: GeneratedLocation, group: String) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for node: Node3D in location.get_node(group).get_children():
		positions.append(node.position)
	return positions


func _to_landing_site(location: GeneratedLocation, at: Vector3) -> float:
	var site: Rect2 = location.landing_site
	var offset: Vector2 = (Vector2(at.x, at.z) - site.get_center()).abs() - site.size * 0.5
	return offset.max(Vector2.ZERO).length()


func _scatter_bodies(location: GeneratedLocation) -> Array[RID]:
	var bodies: Array[RID] = []
	for child: Node in location.get_node("Scatter").get_children():
		if child is StaticBody3D:
			bodies.append((child as StaticBody3D).get_rid())
	return bodies
