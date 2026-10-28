extends GutTest
## What stands on a generated location: ore fields and nests where players and aliens get to,
## the scatter, the lanes kept free and the apex.

const SWEEP := preload("res://tests/support/location_sweep.gd")
const REAL_TIME := preload("res://tests/support/real_time.gd")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")
const OVERGROWTH: LocationBiome = preload("res://game/locations/biomes/overgrowth.tres")
const FROST: LocationBiome = preload("res://game/locations/biomes/frost.tres")
const GLASS: LocationBiome = preload("res://game/locations/biomes/glass.tres")


## Ores and nests stand on the ground, where players can walk to from the ship.
func test_ores_and_nests_are_reachable_and_on_the_ground() -> void:
	for world_seed: int in [1, 2, 3]:
		var location: GeneratedLocation = SWEEP.generate(self, world_seed)
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
	var location: GeneratedLocation = SWEEP.generate(self, 5)
	var fields: float = location.layout.areas.size() * location.biome.ore_fields_per_area
	assert_gt(location.get_node("OreNodes").get_child_count(), fields / 2.0)
	assert_gt(location.get_node("AlienNests").get_child_count(), 0)


func test_nest_factor_scales_the_nests() -> void:
	var few: GeneratedLocation = SWEEP.generate(self, 5, DUST, 0.3)
	var normal: GeneratedLocation = SWEEP.generate(self, 5)
	var nests: int = few.get_node("AlienNests").get_child_count()
	assert_gt(nests, 0)
	assert_lte(nests, roundi(few.layout.areas.size() * DUST.nests_per_area * 0.3))
	assert_gt(normal.get_node("AlienNests").get_child_count(), nests)


## The first ore fields are close to the ramp and of the most common ore; nests keep away.
func test_common_ore_close_to_ship_and_nests_far() -> void:
	for world_seed: int in [1, 2, 3]:
		var location: GeneratedLocation = SWEEP.generate(self, world_seed)
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
				location.biome.nest_min_distance * LocationSites.NEST_STRAIGHT_SHARE
			)


## Plants and rocks grow, but not on the landing site; blocking ones have colliders.
func test_scatter_keeps_landing_site_free() -> void:
	var location: GeneratedLocation = SWEEP.generate(self, 4, OVERGROWTH)
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


## Plants and rocks that block, ore nodes and nests keep a lane free along every pass.
func test_lanes_stay_free() -> void:
	var location: GeneratedLocation = SWEEP.generate(self, 4, OVERGROWTH)
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


## Aliens find a way from their nests to the ship.
func test_navigation_reaches_nests() -> void:
	await _check_navigation(SWEEP.generate(self, 2))


## Aliens walk around the gaps to the next bridge (a test of its own: locations in one test share
## the navigation map).
func test_navigation_goes_around_gaps() -> void:
	await _check_navigation(SWEEP.generate(self, 2, FROST))


## Aliens climb the ramps between the Glass plains' terraces and get through the shard gardens.
func test_navigation_climbs_ramps() -> void:
	await _check_navigation(SWEEP.generate(self, 1, GLASS))


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


## Some locations from tier 3 on have the hive's apex roaming between areas away from the landing.
func test_the_apex_roams_some_locations() -> void:
	var hive: AlienHive = load("res://game/aliens/hive/hive.tres")
	var chance: float = hive.apex_chance
	hive.apex_chance = 1.0
	var low: GeneratedLocation = SWEEP.LOCATION.instantiate() as GeneratedLocation
	low.world_seed = 5
	low.biome = DUST
	low.area_count = SWEEP.BUILT_AREAS
	low.alien_tier = hive.apex_from_tier - 1
	add_child_autofree(low)
	var high: GeneratedLocation = SWEEP.LOCATION.instantiate() as GeneratedLocation
	high.world_seed = 5
	high.biome = DUST
	high.area_count = SWEEP.BUILT_AREAS
	high.alien_tier = hive.apex_from_tier
	add_child_autofree(high)
	hive.apex_chance = chance
	assert_null(low.get_node_or_null(^"Apex"), "not before its tier")
	var lair := high.get_node_or_null(^"Apex") as ApexLair
	assert_not_null(lair)
	assert_eq(lair.apex.strain, hive.apex)
	assert_false(lair.route.is_empty())
	for point: Vector3 in lair.route:
		var at := Vector2(point.x, point.z)
		assert_gte(high.landing_distance(at), GeneratedLocation.APEX_LANDING_DISTANCE)
		assert_true(high.is_reachable(point.x, point.z))


func _to_landing_site(location: GeneratedLocation, at: Vector3) -> float:
	var site: Rect2 = location.landing_site
	var offset: Vector2 = (Vector2(at.x, at.z) - site.get_center()).abs() - site.size * 0.5
	return offset.max(Vector2.ZERO).length()
