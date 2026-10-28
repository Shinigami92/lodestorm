extends GutTest
## Where a generated location's ore nodes and nests go (`LocationSites`), and the generator's
## random streams, one per stage.

const SWEEP := preload("res://tests/support/location_sweep.gd")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")
const FROST: LocationBiome = preload("res://game/locations/biomes/frost.tres")
const SALT: LocationBiome = preload("res://game/locations/biomes/salt.tres")


## Each stage draws from its own stream: the same for the same seed, independent of the others.
func test_each_stage_has_its_own_stream() -> void:
	var ores: RandomNumberGenerator = GeneratedLocation.random_stream(7, "ores")
	var again: RandomNumberGenerator = GeneratedLocation.random_stream(7, "ores")
	var nests: RandomNumberGenerator = GeneratedLocation.random_stream(7, "nests")
	var other_seed: RandomNumberGenerator = GeneratedLocation.random_stream(8, "ores")
	var first: int = ores.randi()
	assert_eq(again.randi(), first, "same seed, same stage")
	assert_ne(nests.randi(), first, "another stage")
	assert_ne(other_seed.randi(), first, "another seed")


## Every site knows its area: ore fields lie in theirs, the nests' areas are far enough from the
## ship.
func test_sites_know_their_area() -> void:
	var location: GeneratedLocation = SWEEP.plan(3, DUST)
	assert_gt(location.sites.ores.size(), 0)
	assert_gt(location.sites.nests.size(), 0)
	for ore: LocationSites.OreSite in location.sites.ores:
		var at := Vector2(ore.position.x, ore.position.z)
		# A field's center lies within 0.8 of its area's radius, its nodes around that.
		var reach: float = ore.area.radius * 0.8 + LocationSites.FIELD_SPREAD
		if ore.area.kind != LocationLayout.Kind.LANDING:
			assert_lt(at.distance_to(ore.area.center), reach, "ore in its area")
	for nest: LocationSites.NestSite in location.sites.nests:
		assert_gte(nest.area.distance, DUST.nest_min_distance, "nest area far enough")
	location.free()


## Every nest hollow holds a rich field of the location's rarest or second rarest ore (the only
## rich nodes), and a hollow's two nests lie on either side of it.
func test_nest_hollows_hold_a_rich_field_between_their_nests() -> void:
	var between: int = 0
	for biome: LocationBiome in [FROST, SALT]:
		var found: Array[OreType] = OreCatalog.sorted(biome.ores)
		var rare: Array[OreType] = found.slice(-2)
		for world_seed: int in SWEEP.seeds(biome, 2):
			var location: GeneratedLocation = SWEEP.plan(world_seed, biome, [], SWEEP.VIEW, 16)
			var label: String = "%s seed %d" % [biome.display_name, world_seed]
			for site: LocationSites.OreSite in location.sites.ores:
				if site.rich:
					assert_eq(site.area.kind, LocationLayout.Kind.NEST_HOLLOW, label)
					assert_has(rare, site.ore, label)
			for area: LocationLayout.Area in location.layout.areas:
				if area.kind != LocationLayout.Kind.NEST_HOLLOW:
					continue
				var field: Vector2 = _rich_field(location, area)
				assert_ne(field, Vector2.INF, "%s: a rich field in every hollow" % label)
				var nests: Array[Vector2] = []
				for nest: LocationSites.NestSite in location.sites.nests:
					if nest.area == area:
						nests.append(Vector2(nest.position.x, nest.position.z))
				if nests.size() == 2 and field != Vector2.INF:
					assert_lt((nests[0] - field).dot(nests[1] - field), 0.0, label)
					between += 1
			location.free()
	assert_gt(between, 0, "some hollows have both nests")


## The center of `area`'s rich field, or `Vector2.INF` when it has none.
func _rich_field(location: GeneratedLocation, area: LocationLayout.Area) -> Vector2:
	var sum := Vector2.ZERO
	var nodes: int = 0
	for site: LocationSites.OreSite in location.sites.ores:
		if site.rich and site.area == area:
			sum += Vector2(site.position.x, site.position.z)
			nodes += 1
	return sum / nodes if nodes > 0 else Vector2.INF
