extends GutTest
## Where a generated location's ore nodes and nests go (`LocationSites`), and the generator's
## random streams, one per stage.

const SWEEP := preload("res://tests/support/location_sweep.gd")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")


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
