extends GutTest
## The built features of the biomes with their own geography: lava and vents in the Ash fields,
## shard fences and shard gardens in the Glass plains, growth walls, mud and fungal groves in the
## Overgrowth.

const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
const ASH: LocationBiome = preload("res://game/locations/biomes/ash.tres")
const GLASS: LocationBiome = preload("res://game/locations/biomes/glass.tres")
const OVERGROWTH: LocationBiome = preload("res://game/locations/biomes/overgrowth.tres")
const AREAS: int = 6


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


## A built Glass plains location: shard fences stand along its gaps' edges, its shard gardens hold
## the shards (the hazard) and the spire clusters, which grow nowhere else.
func test_fences_and_shard_gardens() -> void:
	var location: GeneratedLocation = _generate(1, GLASS)
	var spikes: int = 0
	for chunk: MultiMeshInstance3D in location.get_node("Fence").get_children():
		assert_eq(chunk.multimesh.mesh, GLASS.fence)
		spikes += chunk.multimesh.instance_count
	var edges: int = location.planned_edges().size() >> 1
	assert_gt(spikes, edges, "a spike or more on every wall")
	var shards: Array[Node] = location.get_node("Hazards").get_children()
	assert_gt(shards.size(), 0)
	for patch: Node in shards:
		assert_is(patch, GroundShards)
		assert_eq((patch as GroundShards).damage_per_second, GLASS.hazard_damage)
	var gardens: Array[LocationLayout.Kind] = [LocationLayout.Kind.SHARD_GARDEN]
	var spires: int = 0
	for child: Node in location.get_node("Scatter").get_children():
		if child is StaticBody3D and child.name.begins_with("ShardSpire"):
			for shape: CollisionShape3D in child.get_children():
				spires += 1
				var at := Vector2(shape.position.x, shape.position.z)
				assert_true(location.is_in_area_of(at, gardens), str(at))
	assert_gt(spires, 0)


## A built Overgrowth location: its growth walls stop walking and shots, stalks grow on the growth
## band, its mires hold level mud pools that slow, its fungal groves the giant stalks, which grow
## nowhere else.
func test_growth_walls_mud_and_groves() -> void:
	var location: GeneratedLocation = null
	for world_seed: int in range(1, 6):
		var candidate: GeneratedLocation = _generate(world_seed, OVERGROWTH)
		var kinds: Array[LocationLayout.Kind] = []
		for area: LocationLayout.Area in candidate.layout.areas:
			kinds.append(area.kind)
		if LocationLayout.Kind.MIRE in kinds and LocationLayout.Kind.FUNGAL_GROVE in kinds:
			location = candidate
			break
	assert_not_null(location, "a seed with a mire and a grove")
	var edges := location.get_node("GapEdges") as StaticBody3D
	assert_eq(edges.collision_layer, PhysicsLayers.WORLD, "stop shots too")
	await wait_physics_frames(2)
	# A shot along the ground across a wall is stopped (by the wall, or the ground rising to it).
	var lines: PackedVector2Array = location.planned_edges()
	var shots: int = 0
	var on_walls: int = 0
	var space: PhysicsDirectSpaceState3D = location.get_world_3d().direct_space_state
	for i: int in range(0, lines.size(), 2 * maxi(1, lines.size() >> 5)):
		var middle: Vector2 = (lines[i] + lines[i + 1]) * 0.5
		var across: Vector2 = (lines[i + 1] - lines[i]).orthogonal().normalized() * 1.5
		var from_at: Vector2 = middle - across
		if not location.is_reachable(from_at.x, from_at.y):
			from_at = middle + across
			across = -across
		var height: float = location.terrain.height_at(from_at.x, from_at.y) + 1.2
		var from := Vector3(from_at.x, height, from_at.y)
		var to := Vector3(middle.x + across.x, height, middle.y + across.y)
		var ray := PhysicsRayQueryParameters3D.create(
			location.to_global(from), location.to_global(to), PhysicsLayers.SHOTS
		)
		var hit: Dictionary = space.intersect_ray(ray)
		shots += 1
		assert_false(hit.is_empty(), "a shot through the growth at %s" % middle)
		if not hit.is_empty() and hit[&"collider"] == edges:
			on_walls += 1
	assert_gt(on_walls * 2, shots, "most stopped by the walls")
	# Growth on the band.
	var stalks: int = 0
	for child: Node in location.get_node("Scatter").get_children():
		if child is MultiMeshInstance3D and child.name.begins_with("GrowthStalk"):
			stalks += (child as MultiMeshInstance3D).multimesh.instance_count
	assert_gt(stalks, 100)
	# Mud in the mires' pools, a bit lower than their shore.
	var pools: Array[Node] = location.get_node("Hazards").get_children()
	assert_gt(pools.size(), 2)
	for pool: Node in pools:
		assert_is(pool, GroundMud)
		var mud := pool as GroundMud
		assert_eq(mud.speed, OVERGROWTH.hazard_speed)
		# Level (no bumps), below the swells it lies in.
		var center := Vector2(mud.position.x, mud.position.z)
		var level: float = location.terrain.height_at(center.x, center.y)
		for step: int in 8:
			var at: Vector2 = (
				center + Vector2.from_angle(step * TAU / 8.0) * (mud.radius - location.cell)
			)
			assert_almost_eq(location.terrain.height_at(at.x, at.y), level, 0.05, str(at))
	# The groves' stalks.
	var groves: Array[LocationLayout.Kind] = [LocationLayout.Kind.FUNGAL_GROVE]
	var grove_stalks: int = 0
	for child: Node in location.get_node("Scatter").get_children():
		if child is StaticBody3D and child.name.begins_with("Grove"):
			for shape: CollisionShape3D in child.get_children():
				grove_stalks += 1
				var at := Vector2(shape.position.x, shape.position.z)
				assert_true(location.is_in_area_of(at, groves), str(at))
	assert_gt(grove_stalks, 3)


## A smaller world than in the game, so the tests stay quick.
func _generate(world_seed: int, biome: LocationBiome) -> GeneratedLocation:
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = world_seed
	location.biome = biome
	location.area_count = AREAS
	add_child_autofree(location)
	return location
