extends GutTest
## How generated locations are shaped: the rock towards the camera, ore pockets and nest hollows.
## Swept over many seeds.

const SWEEP := preload("res://tests/support/location_sweep.gd")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")
const SWEEP_SEEDS: Array[int] = [1, 2, 3, 4, 5]
## Areas of the locations compared with and without the camera's view.
const VIEW_AREAS: int = 6


## The rarest ore waits in the ore pockets; nest hollows hold nests, not ore.
func test_ore_pockets_and_nest_hollows() -> void:
	var found: Array[OreType] = OreCatalog.sorted(DUST.ores)
	var rarest: OreType = found[found.size() - 1]
	for world_seed: int in SWEEP_SEEDS:
		var location: GeneratedLocation = SWEEP.plan(world_seed, DUST)
		var sites: Array[Vector3] = location.planned_ore_sites()
		var types: Array[OreType] = location.planned_ore_types()
		for area: LocationLayout.Area in location.layout.areas:
			var inside: Array[OreType] = []
			for i: int in sites.size():
				if Vector2(sites[i].x, sites[i].z).distance_to(area.center) < area.radius * 1.3:
					inside.append(types[i])
			if area.kind == LocationLayout.Kind.ORE_POCKET:
				assert_has(inside, rarest, "seed %d" % world_seed)
			elif area.kind == LocationLayout.Kind.NEST_HOLLOW:
				assert_eq(inside.size(), 0, "seed %d: ore in the hollow" % world_seed)
				assert_gt(_nests_in(location, area), 0, "seed %d: nests in the hollow" % world_seed)
		location.free()


## The rock on the camera's side stays low enough to see over: it only ever gets lower than
## without the camera's view, by a lot in places. (Gaps never hide anything.)
func test_rock_stays_low_on_the_camera_side() -> void:
	for biome: LocationBiome in SWEEP.BIOMES:
		if biome.barrier != LocationBiome.Barrier.WALLS:
			continue
		var viewed: GeneratedLocation = SWEEP.plan(3, biome, [], SWEEP.VIEW, VIEW_AREAS)
		var flat: GeneratedLocation = SWEEP.plan(3, biome, [], Vector3.ZERO, VIEW_AREAS)
		var lower: int = 0
		var higher: int = 0
		var side: int = viewed.terrain.cells + 1
		for i: int in viewed.terrain.heights.size():
			# On the rock.
			var at: Vector3 = viewed.terrain.point(i % side, floori(i / float(side)))
			if viewed.is_reachable(at.x, at.z) or flat.is_reachable(at.x, at.z):
				continue
			# Nor where the ground flattened under a site or a map part blends back (they lie a bit
			# differently with the view).
			if _near_site(viewed, at) or _near_site(flat, at):
				continue
			var difference: float = viewed.terrain.heights[i] - flat.terrain.heights[i]
			if difference > 0.01:
				higher += 1
			elif difference < -3.0:
				lower += 1
		assert_eq(higher, 0, biome.display_name)
		assert_gt(lower, 100, biome.display_name)
		viewed.free()
		flat.free()


func _near_site(location: GeneratedLocation, at: Vector3) -> bool:
	var point := Vector2(at.x, at.z)
	var reach: float = LocationParts.FALLOFFS.max() + location.cell
	for part: LocationParts.Placed in location.parts.placed:
		var center := Vector2(part.origin.x, part.origin.z)
		if center.distance_to(point) < part.info.footprint + reach:
			return true
	reach = GeneratedLocation.SITE_FALLOFF + location.cell
	for nest: Vector3 in location.planned_nest_sites():
		if Vector2(nest.x, nest.z).distance_to(point) < GeneratedLocation.NEST_SITE_RADIUS + reach:
			return true
	for ore: Vector3 in location.planned_ore_sites():
		if Vector2(ore.x, ore.z).distance_to(point) < GeneratedLocation.ORE_SITE_RADIUS + reach:
			return true
	return false


func _nests_in(location: GeneratedLocation, area: LocationLayout.Area) -> int:
	var nests: int = 0
	for nest: Vector3 in location.planned_nest_sites():
		if Vector2(nest.x, nest.z).distance_to(area.center) < area.radius * 1.3:
			nests += 1
	return nests
