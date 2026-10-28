extends GutTest
## The late deposit (`LateDeposit`): its impact site planned with the location (a far crater, its
## ore), waiting hidden in a built one (the walkable area baked around the meteorite already), and
## the meteor coming down during a run.

const SWEEP := preload("res://tests/support/location_sweep.gd")
const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const CRATER: PackedScene = preload("res://game/locations/parts/meteor_crater.tscn")
const ORE_NODE: PackedScene = preload("res://game/mining/ore_node.tscn")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")


## The rarest signature ore, else the rarest mid ore, else the rarest.
func test_deposit_ore_is_the_signature_ore_or_the_rarest_mid_one() -> void:
	var common: Array[OreType] = []
	var mid: Array[OreType] = []
	var signature: Array[OreType] = []
	for ore_type: OreType in OreCatalog.all().ores:
		match ore_type.band:
			OreType.Band.COMMON:
				common.append(ore_type)
			OreType.Band.MID:
				mid.append(ore_type)
			OreType.Band.SIGNATURE:
				signature.append(ore_type)
	var found: Array[OreType] = OreCatalog.sorted([common[0], mid[0], mid[1], signature[0]])
	assert_eq(LocationSites.deposit_ore(found), signature[0], "the signature ore")
	found = OreCatalog.sorted([common[0], common[1], mid[0], mid[1]])
	assert_eq(LocationSites.deposit_ore(found), found[3], "the rarest mid ore")
	found = OreCatalog.sorted([common[0], common[1]])
	assert_eq(LocationSites.deposit_ore(found), found[1], "the rarest")


## Every location has one impact site, far out (a crater, unless its part found no room there and
## went to the next area), with the deposit's ore on its markers (rich); no other site is late.
func test_impact_site_is_a_far_crater_with_its_ore() -> void:
	var locations: int = 0
	var craters: int = 0
	for biome: LocationBiome in SWEEP.BIOMES:
		for world_seed: int in SWEEP.seeds(biome, 2):
			var location: GeneratedLocation = SWEEP.plan(world_seed, biome)
			var label: String = "%s seed %d" % [biome.display_name, world_seed]
			var late: LocationParts.Placed = location.parts.late_part()
			assert_not_null(late, label)
			if not late:
				location.free()
				continue
			locations += 1
			if late.area.kind == LocationLayout.Kind.CRATER:
				craters += 1
			assert_gt(late.area.distance, location.layout.farthest() / 3.0, label)
			var found: Array[OreType] = OreCatalog.sorted(biome.ores)
			var sites: int = 0
			for site: LocationSites.OreSite in location.sites.ores:
				if site.late:
					sites += 1
					assert_eq(site.area, late.area, label)
					assert_true(site.rich, label)
					assert_eq(site.ore, LocationSites.deposit_ore(found), label)
			assert_eq(sites, late.info.count(PartMarker.Kind.ORE), label)
			location.free()
	assert_gte(craters, locations - 1, "nearly always in its crater")


## Built, it waits: the meteorite hidden, without collision and off the hologram, its ore nodes
## outside the tree, an obstacle for the walkable area per collider; it comes within `TIMES`.
func test_waits_hidden_until_the_impact() -> void:
	var location: GeneratedLocation = SWEEP.generate(self, 5)
	var deposit := location.get_node(^"LateDeposit") as LateDeposit
	assert_not_null(deposit)
	assert_between(deposit.at, LateDeposit.TIMES.x, LateDeposit.TIMES.y)
	assert_false(deposit.part.visible)
	assert_false(deposit.part.is_in_group(HoloTable.LANDMARK_GROUP))
	var shapes: int = 0
	for body: Node in deposit.part.find_children("*", "CollisionObject3D", true, false):
		assert_eq((body as CollisionObject3D).collision_layer, 0)
		shapes += body.find_children("*", "CollisionShape3D", false, false).size()
	assert_eq(deposit.find_children("*", "NavigationObstacle3D", false, false).size(), shapes)
	assert_false(deposit.ore_nodes.is_empty())
	for node: OreNode in deposit.ore_nodes:
		assert_false(node.is_inside_tree())
		assert_true(node.rich)
	var built: int = location.get_node(^"OreNodes").get_child_count()
	assert_eq(built + deposit.ore_nodes.size(), location.sites.ores.size())


## The walkable area is baked with the meteorite already there: none under its middle.
func test_walkable_area_leaves_the_meteorite_out() -> void:
	var location: GeneratedLocation = SWEEP.generate(self, 5)
	var navigation := location.get_node(^"Navigation") as LocationNavigation
	if not navigation.is_baked():
		await wait_for_signal(navigation.baked, 30.0)
	assert_true(navigation.is_baked())
	var deposit := location.get_node(^"LateDeposit") as LateDeposit
	var meteorite: Vector3 = (deposit.part.get_node(^"Meteorite") as Node3D).global_position
	var mesh: NavigationMesh = navigation.navigation_mesh
	var under: int = 0
	var vertices: PackedVector3Array = mesh.get_vertices()
	for i: int in mesh.get_polygon_count():
		var outline := PackedVector2Array()
		for index: int in mesh.get_polygon(i):
			var vertex: Vector3 = navigation.global_transform * vertices[index]
			outline.append(Vector2(vertex.x, vertex.z))
		if Geometry2D.is_point_in_polygon(Vector2(meteorite.x, meteorite.z), outline):
			under += 1
	assert_eq(under, 0, "no walkable ground under the meteorite")
	# The crater around it is walkable.
	var beside: Vector3 = deposit.global_position + Vector3(5.5, 0.0, -2.0)
	assert_true(location.is_reachable(beside.x, beside.z))


## During a run, at its time: the streak, then the impact: the meteorite and its ore appear, the
## beam rises, the pilot calls in and the nearest nest sends a pack.
func test_meteor_comes_down_during_a_run() -> void:
	var map: Node3D = TEST_MAP.instantiate()
	add_child_autofree(map)
	var mission := map.get_node(^"Mission") as Mission
	var ship := map.get_node(^"Ship") as Ship
	var player := map.get_node(^"Player") as Player
	var location := map.get_node(NodePath(Voyage.LOCATION_NAME)) as Node3D
	var deposit: LateDeposit = _add_deposit(location, Vector3(60.0, 0.0, 20.0))
	deposit.at = 0.01
	watch_signals(GameEvents.bus)
	await wait_physics_frames(2)
	assert_eq(deposit.state, LateDeposit.State.WAITING, "no run yet")
	mission.state = Mission.State.OPEN
	player.global_position = ship.to_global(Vector3(22.0, 0.0, 0.0))
	player.reset_physics_interpolation()
	await wait_physics_frames(5)
	mission.time_left = mission.duration() * 0.98
	await wait_physics_frames(2)
	assert_eq(deposit.state, LateDeposit.State.FALLING)
	assert_false(deposit.part.visible, "still falling")
	await wait_physics_frames(roundi(LateDeposit.FALL_TIME * Engine.physics_ticks_per_second) + 2)
	assert_true(deposit.has_landed())
	assert_true(deposit.part.visible)
	assert_true(deposit.part.is_in_group(HoloTable.LANDMARK_GROUP))
	assert_eq((deposit.part.get_node(^"Meteorite") as StaticBody3D).collision_layer, 1)
	assert_true(deposit.ore_nodes[0].is_inside_tree())
	assert_true(deposit.ore_nodes[0].is_in_group(OreNode.GROUP))
	assert_not_null(deposit.get_beam())
	assert_signal_emitted(GameEvents.bus, "deposit_landed")
	assert_ne(player.radio.get_line(), "", "the pilot calls in")
	var hunters: int = 0
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		hunters += nest.get_hunters().size()
	assert_gt(hunters + AlienNest.waiting_load(get_tree()), 0.0, "the nearest nest sends a pack")


## Comes once: falling again does nothing.
func test_comes_once() -> void:
	var holder := Node3D.new()
	add_child_autofree(holder)
	var deposit: LateDeposit = _add_deposit(holder, Vector3.ZERO)
	deposit.fall()
	await wait_physics_frames(roundi(LateDeposit.FALL_TIME * Engine.physics_ticks_per_second) + 2)
	assert_true(deposit.has_landed())
	deposit.fall()
	assert_true(deposit.has_landed(), "no second fall")
	assert_eq(deposit.ore_nodes[0].get_parent(), holder)


## A late deposit with a meteor crater part and one ore node, under `location` at `at`.
func _add_deposit(location: Node3D, at: Vector3) -> LateDeposit:
	var part := CRATER.instantiate() as MapPart
	part.position = at
	location.add_child(part)
	var node := ORE_NODE.instantiate() as OreNode
	node.ore_type = MERIDINE
	node.rich = true
	node.position = at + Vector3(5.6, 0.0, -2.0)
	var deposit := LateDeposit.new()
	deposit.part = part
	deposit.ore_nodes = [node]
	deposit.ore_holder = location
	deposit.position = at
	location.add_child(deposit)
	return deposit
