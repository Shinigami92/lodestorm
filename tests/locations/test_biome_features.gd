extends GutTest
## The built features of the biomes with their own geography: lava and vents in the Ash fields,
## shard fences and shard gardens in the Glass plains.

const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
const ASH: LocationBiome = preload("res://game/locations/biomes/ash.tres")
const GLASS: LocationBiome = preload("res://game/locations/biomes/glass.tres")
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


## A smaller world than in the game, so the tests stay quick.
func _generate(world_seed: int, biome: LocationBiome) -> GeneratedLocation:
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = world_seed
	location.biome = biome
	location.area_count = AREAS
	add_child_autofree(location)
	return location
