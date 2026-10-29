extends GutTest
## A generated location's ground: the same for the same seed, flat at the landing site, hills and
## cliffs, its collision, the gaps' edges; and the map landing on it (what stands on it:
## `test_generated_location_sites.gd`).

const TEST_MAP: PackedScene = preload("res://game/maps/main.tscn")
const SWEEP := preload("res://tests/support/location_sweep.gd")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")
const OVERGROWTH: LocationBiome = preload("res://game/locations/biomes/overgrowth.tres")
const FROST: LocationBiome = preload("res://game/locations/biomes/frost.tres")


func after_each() -> void:
	# What the game frees a frame late (a swapped model, weapon or view) isn't counted as an orphan.
	await wait_process_frames(1)


func test_same_seed_same_world() -> void:
	var first: GeneratedLocation = SWEEP.generate(self, 7)
	var second: GeneratedLocation = SWEEP.generate(self, 7)
	assert_eq(first.terrain.heights, second.terrain.heights)
	assert_eq(_positions(first, "OreNodes"), _positions(second, "OreNodes"))
	assert_eq(_positions(first, "AlienNests"), _positions(second, "AlienNests"))
	var other: GeneratedLocation = SWEEP.generate(self, 8)
	assert_ne(first.terrain.heights, other.terrain.heights)


func test_without_seed_every_world_is_new() -> void:
	var first: GeneratedLocation = SWEEP.generate(self, 0)
	var second: GeneratedLocation = SWEEP.generate(self, 0)
	assert_ne(first.world_seed, 0)
	assert_ne(first.world_seed, second.world_seed)


func test_picks_a_biome_when_none_is_set() -> void:
	var location := SWEEP.LOCATION.instantiate() as GeneratedLocation
	location.area_count = SWEEP.BUILT_AREAS
	add_child_autofree(location)
	assert_has([DUST, OVERGROWTH], location.biome)


## The ship stands at the origin on flat ground at height 0, with room in front of the ramp.
func test_landing_site_is_flat() -> void:
	for biome: LocationBiome in SWEEP.BIOMES:
		var location: GeneratedLocation = SWEEP.generate(self, 3, biome)
		var site: Rect2 = location.landing_site
		for x: float in range(int(site.position.x), int(site.end.x), 4):
			for z: float in range(int(site.position.y), int(site.end.y), 4):
				assert_almost_eq(location.terrain.height_at(x, z), 0.0, 0.001)


func test_world_has_hills_and_cliffs() -> void:
	var location: GeneratedLocation = SWEEP.generate(self, 11)
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


## The ground is drawn with the biome's material; scree lies at the foot of cliffs, not on the
## landing site.
func test_ground_material_and_scree() -> void:
	var location: GeneratedLocation = SWEEP.generate(self, 11)
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


## The ground's collision matches `height_at`, which places everything.
func test_collision_matches_heights() -> void:
	var location: GeneratedLocation = SWEEP.generate(self, 6)
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


## Walls along the gaps' edges stop players and aliens but not shots; the slick ice is there.
func test_gap_edges_block_walking_not_shots() -> void:
	var location: GeneratedLocation = SWEEP.generate(self, 2, FROST)
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


## The game's map lands the ship on the generated world's landing site.
func test_test_map_lands_ship_on_generated_world() -> void:
	var map := TEST_MAP.instantiate() as Node3D
	add_child_autofree(map)
	var voyage := map.get_node("Voyage") as Voyage
	assert_true(voyage.select(voyage.offers[0]))
	voyage.skip_flight()
	var location := map.get_node("Location") as GeneratedLocation
	var ship := map.get_node("Ship") as Ship
	assert_not_null(location)
	var length: float = voyage.offers[0].length
	assert_eq(location.area_count, roundi(voyage.settings.location_areas * length))
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
	var direct: GeneratedLocation = SWEEP.generate(self, 5)
	var planned := SWEEP.LOCATION.instantiate() as GeneratedLocation
	planned.world_seed = 5
	planned.biome = DUST
	planned.area_count = SWEEP.BUILT_AREAS
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


func _positions(location: GeneratedLocation, group: String) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for node: Node3D in location.get_node(group).get_children():
		positions.append(node.position)
	return positions


func _scatter_bodies(location: GeneratedLocation) -> Array[RID]:
	var bodies: Array[RID] = []
	for child: Node in location.get_node("Scatter").get_children():
		if child is StaticBody3D:
			bodies.append((child as StaticBody3D).get_rid())
	return bodies
