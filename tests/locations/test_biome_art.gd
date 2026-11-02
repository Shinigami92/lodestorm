extends GutTest
## The biomes' own art: every scatter type, cliff chunk, fence and hazard dressing finds its mesh
## in its model kit, and the cliff chunks stand at the cliffs' feet, their faces towards the open
## ground.

const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
const SWEEP := preload("res://tests/support/location_sweep.gd")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")


## The sweeps' biome list (every test's over all biomes) has every biome in the biomes' folder, so
## a new one is covered (its order picks the sweeps' seeds: a new biome goes at the end).
func test_the_sweeps_know_every_biome() -> void:
	var folder: String = "res://game/locations/biomes"
	var paths: Array[String] = []
	for file: String in ResourceLoader.list_directory(folder):
		if file.ends_with(".tres"):
			paths.append(folder.path_join(file))
	var known: Array[String] = []
	for biome: LocationBiome in SWEEP.BIOMES:
		known.append(biome.resource_path)
	paths.sort()
	known.sort()
	assert_eq(known, paths)


func test_every_part_has_a_mesh() -> void:
	for biome: LocationBiome in SWEEP.BIOMES:
		var types: Array[ScatterType] = biome.scatter + biome.cliff_dressing
		if biome.fence:
			types.append(biome.fence)
		if biome.hazard_dressing:
			types.append(biome.hazard_dressing)
		for type: ScatterType in types:
			assert_not_null(type.get_mesh(), "%s: %s" % [biome.display_name, type.display_name])


## A built Dust flats location gets cliff chunks.
func test_dust_cliffs_get_chunks() -> void:
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = 3
	location.biome = DUST
	location.area_count = 6
	add_child_autofree(location)
	var count: int = 0
	for chunk: MultiMeshInstance3D in location.get_node("Cliffs").get_children():
		count += chunk.multimesh.instance_count
	assert_gt(count, 10)


## Along a straight cliff (rock rising 6 m east of x = 0, walkable ground west of it), the chunks
## stand at its foot, their faces turned west within `LocationCliffs.TURN`, never on the rock.
func test_chunks_face_the_open_ground() -> void:
	var terrain := LocationTerrain.new(Vector2(-20.0, -20.0), 20, 2.0)
	var reachable := PackedByteArray()
	reachable.resize(terrain.heights.size())
	for z: int in terrain.cells + 1:
		for x: int in terrain.cells + 1:
			var rock: bool = terrain.point(x, z).x >= 0.0
			terrain.set_height(x, z, 6.0 if rock else 0.0)
			reachable[terrain.index(x, z)] = 0 if rock else 1
	var type := ScatterType.new()
	type.model = preload("res://assets/rocks/rocks.glb")
	type.model_part = &"Cliff_a"
	type.max_scale = 3.0
	var cliffs := LocationCliffs.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	cliffs.plan(rng, terrain, [type], reachable, PackedByteArray())
	var placed: Array[Transform3D] = cliffs.placements(terrain)
	assert_gt(placed.size(), 3)
	for at: Transform3D in placed:
		var face: Vector3 = at.basis.z.normalized()
		assert_lt(face.angle_to(Vector3.LEFT), deg_to_rad(LocationCliffs.TURN + 1.0), "faces west")
		assert_lt(at.origin.x, 6.0, "at the foot, not up on the rock")
		assert_gt(at.origin.x, -6.0, "at the foot, not out in the open")
