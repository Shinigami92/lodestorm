extends GutTest

const LOCATION: PackedScene = preload("res://scenes/locations/generated_location.tscn")
const TEST_MAP: PackedScene = preload("res://scenes/maps/test_map.tscn")
const DUST: LocationBiome = preload("res://scenes/locations/biomes/dust.tres")
const OVERGROWTH: LocationBiome = preload("res://scenes/locations/biomes/overgrowth.tres")


## A smaller world than in the game, so the tests stay quick.
func _generate(world_seed: int, biome: LocationBiome = DUST) -> GeneratedLocation:
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = world_seed
	location.biome = biome
	location.size = 320.0
	location.landing_offset = 0.0
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
	location.size = 320.0
	location.landing_offset = 0.0
	add_child_autofree(location)
	assert_has([DUST, OVERGROWTH], location.biome)


## The ship stands at the origin on flat ground at height 0, with room in front of the ramp.
func test_landing_site_is_flat() -> void:
	for biome: LocationBiome in [DUST, OVERGROWTH]:
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
	assert_gt(location.get_node("OreNodes").get_child_count(), location.biome.ore_fields / 2)
	assert_gt(location.get_node("AlienNests").get_child_count(), 0)


## The first ore fields are close to the ramp and of the most common ore; nests keep away.
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
			assert_gte(_to_landing_site(location, nest.position), location.biome.nest_min_distance)


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
func test_navigation_reaches_nests() -> void:
	var location: GeneratedLocation = _generate(2)
	var map: RID = location.get_world_3d().navigation_map
	# The navigation map takes the baked mesh over in the background.
	var outside := Vector3(55.0, 0.0, 0.0)
	await wait_until(
		func() -> bool:
			return NavigationServer3D.map_get_closest_point(map, outside) != Vector3.ZERO,
		5.0
	)
	var start: Vector3 = NavigationServer3D.map_get_closest_point(map, outside)
	for nest: Node3D in location.get_node("AlienNests").get_children():
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			map, start, nest.global_position, true
		)
		assert_gt(path.size(), 1, nest.name)
		if path.size() > 1:
			assert_lt(path[path.size() - 1].distance_to(nest.global_position), 9.0, nest.name)


## The game's map lands the ship on the generated world's landing site.
func test_test_map_lands_ship_on_generated_world() -> void:
	var map := TEST_MAP.instantiate() as Node3D
	add_child_autofree(map)
	var location := map.get_node("Location") as GeneratedLocation
	var ship := map.get_node("Ship") as Ship
	assert_not_null(location)
	assert_eq(location.size, 500.0)
	assert_almost_eq(
		location.global_transform.origin, ship.global_transform.origin, Vector3.ONE * 0.001
	)
	assert_almost_eq(
		location.global_basis.x.dot(ship.global_basis.x), 1.0, 0.001, "same axes as the ship"
	)


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
