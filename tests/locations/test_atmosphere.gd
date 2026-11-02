extends GutTest
## The outside's atmosphere as data: every body the ship lands on has its light, brighter and
## higher inwards, with the star bigger in the sky; every moon sees its planet; every biome has its
## weather; a generated location gets its far ring of land around the map.

const SYSTEM: StarSystem = preload("res://game/world/star_system.tres")
const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
const BIOMES: Array[LocationBiome] = [
	preload("res://game/locations/biomes/ash.tres"),
	preload("res://game/locations/biomes/dust.tres"),
	preload("res://game/locations/biomes/frost.tres"),
	preload("res://game/locations/biomes/glass.tres"),
	preload("res://game/locations/biomes/overgrowth.tres"),
	preload("res://game/locations/biomes/salt.tres"),
]


func _landing_bodies() -> Array[CelestialBody]:
	return SYSTEM.bodies.filter(
		func(body: CelestialBody) -> bool: return not body.regions.is_empty()
	)


func test_every_landing_body_has_its_light() -> void:
	for body: CelestialBody in _landing_bodies():
		assert_not_null(body.light, body.display_name)


## The sun stands higher and the star looks bigger the farther in a body lies (by tier).
func test_light_grows_inwards() -> void:
	for body: CelestialBody in _landing_bodies():
		for other: CelestialBody in _landing_bodies():
			if other.tier <= body.tier or not body.light or not other.light:
				continue
			var names: String = "%s < %s" % [body.display_name, other.display_name]
			assert_lt(body.light.sun_elevation, other.light.sun_elevation, names)
			assert_lt(body.light.star_size, other.light.star_size, names)
			assert_true(body.light.star_glare <= other.light.star_glare, names)


func test_every_moon_sees_its_planet() -> void:
	for body: CelestialBody in _landing_bodies():
		if body.kind == CelestialBody.Kind.MOON:
			assert_gt(body.light.planet_size, 0.0, body.display_name)
		else:
			assert_eq(body.light.planet_size, 0.0, body.display_name)


func test_every_biome_has_its_weather() -> void:
	for biome: LocationBiome in BIOMES:
		assert_not_null(biome.weather, biome.display_name)
		if biome.weather:
			assert_false(biome.weather.particles.is_empty(), biome.display_name)
			assert_lt(biome.weather.haze_begin, biome.weather.haze_end, biome.display_name)


## The sky's shader gets a moon's planet as a disc, and no disc on a planet.
func test_sky_shows_a_moons_planet() -> void:
	var sky := WeatherSky.new()
	var moon: CelestialBody = SYSTEM.body_by_id(&"orrel")
	sky.show_body(moon, moon.light, SYSTEM, Vector3.UP)
	assert_gt(sky.material.get_shader_parameter(&"planet_radius") as float, 0.1)
	var planet: CelestialBody = SYSTEM.body_by_id(&"zairen")
	sky.show_body(planet, planet.light, SYSTEM, Vector3.UP)
	assert_eq(sky.material.get_shader_parameter(&"planet_radius") as float, 0.0)


## The far ring reaches well beyond the map on every side and casts no shadow.
func test_location_gets_a_far_ring() -> void:
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = 3
	location.biome = BIOMES[1]
	location.area_count = 6
	add_child_autofree(location)
	var ring := location.get_node_or_null("FarRing") as MeshInstance3D
	assert_not_null(ring)
	if not ring:
		return
	assert_eq(ring.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var bounds: AABB = ring.get_aabb()
	var map: Rect2 = location.terrain.rect()
	var reach: float = LocationFarRing.RINGS[LocationFarRing.RINGS.size() - 1] * 0.9
	assert_lt(bounds.position.x, map.position.x - reach)
	assert_gt(bounds.end.x, map.end.x + reach)
	assert_lt(bounds.position.z, map.position.y - reach)
	assert_gt(bounds.end.z, map.end.y + reach)
