extends GutTest
## Where players can walk in generated locations, swept over every biome. The sweeps share their
## planned locations, planned by the first test that needs them (not in `before_all`, whose time
## the timings in `tests/timings.txt` would miss).

const SWEEP := preload("res://tests/support/location_sweep.gd")
## Seeds per biome.
const BIOME_SEEDS: int = 2

var _locations: Array[GeneratedLocation] = []
var _labels: Array[String] = []


func after_all() -> void:
	for location: GeneratedLocation in _locations:
		location.free()
	_locations.clear()


## Every spot players can walk to leads back to the ship: nothing to fall into for good. Every
## area can be reached, a plateau's top too.
func test_every_walkable_spot_leads_back() -> void:
	_plan()
	for i: int in _locations.size():
		var location: GeneratedLocation = _locations[i]
		var label: String = _labels[i]
		assert_eq(location.stuck_spots(), PackedVector2Array(), label)
		for area: LocationLayout.Area in location.layout.areas:
			assert_true(location.is_reachable(area.center.x, area.center.y), label)
			if area.kind == LocationLayout.Kind.PLATEAU:
				assert_true(location.is_reachable(area.mesa.x, area.mesa.y), label + " mesa")
				var top: float = location.terrain.height_at(area.mesa.x, area.mesa.y)
				var foot: float = location.terrain.height_at(area.center.x, area.center.y)
				assert_gt(top - foot, 3.0, label + " mesa stands out")
		for site: Vector3 in location.planned_ore_sites() + location.planned_nest_sites():
			assert_true(location.is_reachable(site.x, site.z), label)


## Nobody gets onto the rock: walkable ground is only in the areas, the passes and around the
## landing site (and at the foot of their cliffs).
func test_rock_cannot_be_climbed() -> void:
	_plan()
	for i: int in _locations.size():
		var location: GeneratedLocation = _locations[i]
		var terrain: LocationTerrain = location.terrain
		var stray: int = 0
		for z: int in range(0, terrain.cells + 1, 3):
			for x: int in range(0, terrain.cells + 1, 3):
				var at: Vector3 = terrain.point(x, z)
				if location.is_reachable(at.x, at.z) and not _near_open(location, at):
					stray += 1
		assert_eq(stray, 0, _labels[i])


func _plan() -> void:
	if not _locations.is_empty():
		return
	for biome: LocationBiome in SWEEP.BIOMES:
		for world_seed: int in SWEEP.seeds(biome, BIOME_SEEDS):
			_locations.append(SWEEP.plan(world_seed, biome))
			_labels.append("%s seed %d" % [biome.display_name, world_seed])


## Whether `at` lies in an area, a pass or the landing site, or at the foot of their cliffs.
func _near_open(location: GeneratedLocation, at: Vector3) -> bool:
	var point := Vector2(at.x, at.z)
	var slack: float = location.biome.cliff_width + location.cell * 2.0
	var site: Rect2 = location.landing_site.grow(GeneratedLocation.LANDING_MARGIN + slack)
	if site.has_point(point):
		return true
	for area: LocationLayout.Area in location.layout.areas:
		var reach: float = area.radius * (1.0 + 2.0 * GeneratedLocation.AREA_WOBBLE) + slack
		if point.distance_to(area.center) < reach:
			return true
	for way: LocationLayout.Pass in location.layout.passes:
		var reach: float = way.width * 0.5 * (1.0 + 2.0 * GeneratedLocation.PASS_WOBBLE) + slack
		for i: int in range(1, way.points.size()):
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
				point, way.points[i - 1], way.points[i]
			)
			if point.distance_to(closest) < reach:
				return true
	return false
