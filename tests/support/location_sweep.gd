extends RefCounted
## Generated locations for the tests: planned for the sweeps over many seeds and biomes, or built
## small (`generate`). The sweeps are the slowest tests, so they're spread over several scripts,
## which run in parallel (`tools/test.sh`).

const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
## Every biome: what holds for one holds for all.
const BIOMES: Array[LocationBiome] = [
	preload("res://game/locations/biomes/dust.tres"),
	preload("res://game/locations/biomes/overgrowth.tres"),
	preload("res://game/locations/biomes/frost.tres"),
	preload("res://game/locations/biomes/salt.tres"),
	preload("res://game/locations/biomes/ash.tres"),
	preload("res://game/locations/biomes/glass.tres"),
]
## Areas of a planned location.
const AREAS: int = 9
## Areas of a built location (`generate`): smaller than in the game, so the tests stay quick.
const BUILT_AREAS: int = 6
## Where the camera looks in the game when the ship's nose points along -x (isometric).
const VIEW := Vector3(-0.577, -0.577, -0.577)


## Only planned (no nodes): quicker, for sweeps over many seeds. With the camera's view, like in
## the game (`view`). Free it when done.
static func plan(
	world_seed: int,
	biome: LocationBiome,
	set_pieces: Array[PartPlacement] = [],
	view: Vector3 = VIEW,
	areas: int = AREAS
) -> GeneratedLocation:
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = world_seed
	location.biome = biome
	location.area_count = areas
	location.view_direction = view
	location.set_pieces = set_pieces
	location.plan()
	return location


## Built in `test`'s tree (nodes and all, freed after the test), `BUILT_AREAS` big; dust unless
## `biome` is given.
static func generate(
	test: GutTest, world_seed: int, biome: LocationBiome = BIOMES[0], nest_factor: float = 1.0
) -> GeneratedLocation:
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = world_seed
	location.biome = biome
	location.nest_factor = nest_factor
	location.area_count = BUILT_AREAS
	test.add_child_autofree(location)
	return location


## The seeds a sweep plans `biome` with: `count` of them, different for every biome, so the sweeps
## over all biomes cover as many seeds as they plan locations.
static func seeds(biome: LocationBiome, count: int) -> Array[int]:
	var first: int = 1 + BIOMES.find(biome) * count
	var result: Array[int] = []
	for world_seed: int in range(first, first + count):
		result.append(world_seed)
	return result
