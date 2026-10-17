extends GutTest
## The campaign's star system (see GAME_DESIGN.md, Missions): planets from the outside in, one per
## signature ore, their moons, tiers growing towards the star, and biomes that spread the common
## and mid ores.

const SYSTEM: StarSystem = preload("res://game/world/star_system.tres")
const ALL_ORES: OreCatalog = preload("res://game/ores/all_ores.tres")


## Every signature ore has its planet: on the planet itself, or on the moons of one gas giant.
func test_every_signature_ore_has_one_planet() -> void:
	for ore_type: OreType in ALL_ORES.ores:
		if ore_type.band != OreType.Band.SIGNATURE:
			continue
		var planets: Array[CelestialBody] = []
		for body: CelestialBody in SYSTEM.bodies:
			if ore_type in body.signature_ores and _planet_of(body) not in planets:
				planets.append(_planet_of(body))
		assert_eq(planets.size(), 1, ore_type.display_name)
		if planets.size() == 1 and planets[0].kind == CelestialBody.Kind.GAS_GIANT:
			assert_true(planets[0].signature_ores.is_empty(), "a gas giant's ore is on its moons")


## The farther in, the higher the tier: each planet one more than the one outside it; moons have
## their planet's.
func test_tiers_grow_towards_the_star() -> void:
	var planets: Array[CelestialBody] = _planets()
	planets.sort_custom(
		func(a: CelestialBody, b: CelestialBody) -> bool: return a.orbit_radius > b.orbit_radius
	)
	for i: int in planets.size():
		assert_eq(planets[i].tier, i + 1, planets[i].display_name)
	for body: CelestialBody in SYSTEM.bodies:
		if body.kind == CelestialBody.Kind.MOON:
			assert_eq(body.tier, body.orbits.tier, body.display_name)


## Planets have three or four regions and at least one hard one; moons one or two; a gas giant
## none (the ship lands on its moons).
func test_regions_per_body() -> void:
	for body: CelestialBody in SYSTEM.bodies:
		var count: int = body.regions.size()
		match body.kind:
			CelestialBody.Kind.PLANET:
				assert_between(count, 3, 4, body.display_name)
				var dangers: Array = body.regions.map(func(r: Region) -> int: return r.danger)
				assert_has(dangers, MissionBrief.Difficulty.HARD, body.display_name)
			CelestialBody.Kind.MOON:
				assert_between(count, 1, 2, body.display_name)
			_:
				assert_eq(count, 0, body.display_name)


## A moon has a biome its planet doesn't, so its planet's neighbors' ores are reachable early.
func test_moons_bring_another_biome() -> void:
	for body: CelestialBody in SYSTEM.bodies:
		if body.kind != CelestialBody.Kind.MOON:
			continue
		var planet_biomes: Array = body.orbits.regions.map(
			func(r: Region) -> LocationBiome: return r.biome
		)
		var new_biome: bool = false
		for region: Region in body.regions:
			if region.biome not in planet_biomes:
				new_biome = true
		assert_true(new_biome, body.display_name)


## Every common and mid ore lies in two biomes or more, so no single biome holds one back.
func test_common_and_mid_ores_in_several_biomes() -> void:
	var biomes: Array[LocationBiome] = []
	for body: CelestialBody in SYSTEM.bodies:
		for region: Region in body.regions:
			if region.biome not in biomes:
				biomes.append(region.biome)
	assert_eq(biomes.size(), 6, "six biomes")
	for ore_type: OreType in ALL_ORES.ores:
		if ore_type.band == OreType.Band.SIGNATURE:
			continue
		var holding: int = 0
		for biome: LocationBiome in biomes:
			if ore_type in biome.ores:
				holding += 1
		assert_gte(holding, 2, ore_type.display_name)


## Planet names start with different letters, so they read apart in lists (like the ores).
func test_planet_names_start_with_different_letters() -> void:
	var letters: Array[String] = []
	for planet: CelestialBody in _planets():
		var letter: String = planet.display_name.left(1)
		assert_does_not_have(letters, letter, planet.display_name)
		letters.append(letter)


## Only the first planet and its moon are open at the start.
func test_only_the_first_tier_is_open() -> void:
	for body: CelestialBody in SYSTEM.bodies:
		for region: Region in body.regions:
			assert_eq(region.unlocked, body.tier == 1, region.display_name)


func _planets() -> Array[CelestialBody]:
	var planets: Array[CelestialBody] = []
	for body: CelestialBody in SYSTEM.bodies:
		if body.kind in [CelestialBody.Kind.PLANET, CelestialBody.Kind.GAS_GIANT]:
			planets.append(body)
	return planets


## The planet `body` belongs to: itself, or the one a moon orbits.
static func _planet_of(body: CelestialBody) -> CelestialBody:
	return body.orbits if body.kind == CelestialBody.Kind.MOON else body
