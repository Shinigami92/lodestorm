extends GutTest
## How generated locations are shaped: the rock towards the camera, ore pockets and nest hollows,
## the biomes' own shapes (causeways, ridges, slot canyons, buttes, dry washes, terraces). Swept
## over many seeds.

const SWEEP := preload("res://tests/support/location_sweep.gd")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")
const SALT: LocationBiome = preload("res://game/locations/biomes/salt.tres")
const ASH: LocationBiome = preload("res://game/locations/biomes/ash.tres")
const GLASS: LocationBiome = preload("res://game/locations/biomes/glass.tres")
const SWEEP_SEEDS: Array[int] = [1, 2, 3, 4, 5]
## Areas of the locations compared with and without the camera's view.
const VIEW_AREAS: int = 6


## The rarest ore waits in the ore pockets; nest hollows hold only their rich field.
func test_ore_pockets_and_nest_hollows() -> void:
	var found: Array[OreType] = OreCatalog.sorted(DUST.ores)
	var rarest: OreType = found[found.size() - 1]
	for world_seed: int in SWEEP_SEEDS:
		var location: GeneratedLocation = SWEEP.plan(world_seed, DUST)
		for area: LocationLayout.Area in location.layout.areas:
			var inside: Array[OreType] = []
			var rich: int = 0
			for site: LocationSites.OreSite in location.sites.ores:
				var at := Vector2(site.position.x, site.position.z)
				if at.distance_to(area.center) < area.radius * 1.3:
					inside.append(site.ore)
					rich += 1 if site.rich else 0
			if area.kind == LocationLayout.Kind.ORE_POCKET:
				assert_has(inside, rarest, "seed %d" % world_seed)
			elif area.kind == LocationLayout.Kind.NEST_HOLLOW:
				assert_gt(rich, 0, "seed %d: a rich field in the hollow" % world_seed)
				assert_eq(inside.size(), rich, "seed %d: other ore in the hollow" % world_seed)
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


## The Salt pans' causeways rise above the pans: the same world with flat bridges lies lower on
## them, by the rise in their middle.
func test_causeways_are_raised() -> void:
	var flat_salt := SALT.duplicate() as LocationBiome
	flat_salt.bridge_rise = 0.0
	var raised: GeneratedLocation = SWEEP.plan(4, SALT, [], SWEEP.VIEW, VIEW_AREAS)
	var flat: GeneratedLocation = SWEEP.plan(4, flat_salt, [], SWEEP.VIEW, VIEW_AREAS)
	var highest: float = 0.0
	for i: int in raised.terrain.heights.size():
		var difference: float = raised.terrain.heights[i] - flat.terrain.heights[i]
		assert_gt(difference, -0.01)
		highest = maxf(highest, difference)
	assert_almost_eq(highest, SALT.bridge_rise, 0.05)
	raised.free()
	flat.free()


## The Ash fields' rock rises in long, sharp ridges: much higher in places than the cliffs, with
## low ground between the spines.
func test_ash_rock_has_ridges() -> void:
	var location: GeneratedLocation = SWEEP.plan(2, ASH, [], Vector3.ZERO, VIEW_AREAS)
	var tall: int = 0
	var low: int = 0
	var side: int = location.terrain.cells + 1
	for i: int in location.terrain.heights.size():
		var at: Vector3 = location.terrain.point(i % side, floori(i / float(side)))
		if location.is_reachable(at.x, at.z) or location.is_gap(at.x, at.z):
			continue
		if at.y > ASH.wall_height + ASH.rock_relief * 0.8:
			tall += 1
		elif at.y < ASH.wall_height + ASH.rock_relief * 0.2:
			low += 1
	assert_gt(tall, 100, "spines")
	assert_gt(low, tall, "low between them")
	location.free()


## The Dust flats' slot canyons are deep: the same world without their depth has lower rock
## beside them (never higher), by the depth at most.
func test_slot_canyons_are_deep() -> void:
	var shallow_dust := DUST.duplicate() as LocationBiome
	shallow_dust.canyon_depth = 0.0
	var deep: GeneratedLocation = SWEEP.plan(2, DUST, [], Vector3.ZERO, VIEW_AREAS)
	var shallow: GeneratedLocation = SWEEP.plan(2, shallow_dust, [], Vector3.ZERO, VIEW_AREAS)
	var deeper: int = 0
	for i: int in deep.terrain.heights.size():
		var difference: float = deep.terrain.heights[i] - shallow.terrain.heights[i]
		assert_gt(difference, -0.01)
		assert_lt(difference, DUST.canyon_depth + 0.01)
		if difference > DUST.canyon_depth * 0.9:
			deeper += 1
	assert_gt(deeper, 100)
	deep.free()
	shallow.free()


## A butte field's buttes rise as rock with a flat top above the open ground around them, which
## stays walkable; a dry wash's bed lies below its banks.
func test_buttes_and_dry_washes() -> void:
	var buttes: int = 0
	var beds: int = 0
	for world_seed: int in SWEEP_SEEDS:
		var location: GeneratedLocation = SWEEP.plan(world_seed, DUST)
		var terrain: LocationTerrain = location.terrain
		var label: String = "seed %d" % world_seed
		for area: LocationLayout.Area in location.layout.areas:
			for butte: Vector3 in area.buttes:
				buttes += 1
				var center := Vector2(butte.x, butte.y)
				var foot: Vector2 = center + (area.center - center).normalized() * (butte.z + 3.0)
				assert_false(location.is_reachable(center.x, center.y), label)
				assert_true(location.is_reachable(foot.x, foot.y), label)
				var rise: float = (
					terrain.height_at(center.x, center.y) - terrain.height_at(foot.x, foot.y)
				)
				assert_almost_eq(rise, LocationFeatures.BUTTE_HEIGHT, 1.5, label)
			if area.kind != LocationLayout.Kind.DRY_WASH:
				continue
			# Along its bed, from the middle out: the first spot with both banks' ground as it was
			# (the ground under an ore field or nest in the wash is flattened).
			var middle: int = area.bed.size() >> 1
			for step: int in range(1, area.bed.size() - 1):
				var i: int = middle + (step >> 1) * (1 if step % 2 else -1)
				if i < 1 or i > area.bed.size() - 2:
					continue
				var at: Vector2 = area.bed[i]
				var across: Vector2 = (area.bed[i + 1] - area.bed[i - 1]).normalized().orthogonal()
				var bank: Vector2 = (
					at
					+ across * (LocationFeatures.BED_HALF_WIDTH + LocationFeatures.BED_BANK + 1.0)
				)
				if not location.is_reachable(bank.x, bank.y):
					bank = at * 2.0 - bank
				if (
					not location.is_reachable(at.x, at.y)
					or not location.is_reachable(bank.x, bank.y)
					or _near_site(location, Vector3(at.x, 0.0, at.y))
					or _near_site(location, Vector3(bank.x, 0.0, bank.y))
				):
					continue
				beds += 1
				var below: float = terrain.height_at(bank.x, bank.y) - terrain.height_at(at.x, at.y)
				assert_gt(below, LocationFeatures.BED_DEPTH * 0.5, label)
				break
		location.free()
	assert_gt(buttes, 3)
	assert_gt(beds, 0)


## The Glass plains' areas lie on slabs of their own levels, a step apart at most along a pass and
## never below the landing yard next to it; the ramps between them can be walked (see
## `test_location_walkable`). Terrace stairs climb two steps above their area.
func test_terraces() -> void:
	var levels: Dictionary[float, bool] = {}
	var stairs: int = 0
	for world_seed: int in SWEEP_SEEDS:
		var location: GeneratedLocation = SWEEP.plan(world_seed, GLASS)
		var terrain: LocationTerrain = location.terrain
		var areas: Array[LocationLayout.Area] = location.layout.areas
		var label: String = "seed %d" % world_seed
		for way: LocationLayout.Pass in location.layout.passes:
			var step: float = absf(areas[way.from].level - areas[way.to].level)
			assert_lte(step, GLASS.terrace_step + 0.01, label)
			if way.from == 0 or way.to == 0:
				assert_gte(areas[way.to if way.from == 0 else way.from].level, 0.0, label)
		for area: LocationLayout.Area in areas:
			levels[area.level] = true
			var height: float = terrain.height_at(area.center.x, area.center.y)
			if area.kind in [LocationLayout.Kind.BASIN, LocationLayout.Kind.CROSSROADS]:
				assert_almost_eq(height, area.level, GLASS.floor_relief + 0.5, label)
			if area.kind != LocationLayout.Kind.TERRACE_STAIRS:
				continue
			stairs += 1
			var top: Vector2 = area.slabs[1].center
			assert_true(location.is_reachable(top.x, top.y), label + " stairs' top")
			var climb: float = terrain.height_at(top.x, top.y) - height
			assert_almost_eq(climb, GLASS.terrace_step * 2.0, GLASS.floor_relief + 0.5, label)
		location.free()
	assert_gt(levels.size(), 2, "areas on several levels")
	assert_gt(stairs, 0)


func _near_site(location: GeneratedLocation, at: Vector3) -> bool:
	var point := Vector2(at.x, at.z)
	var reach: float = LocationParts.FALLOFFS.max() + location.cell
	for part: LocationParts.Placed in location.parts.placed:
		var center := Vector2(part.origin.x, part.origin.z)
		if center.distance_to(point) < part.info.footprint + reach:
			return true
	reach = GeneratedLocation.SITE_FALLOFF + location.cell
	for nest: Vector3 in location.sites.nest_positions():
		if Vector2(nest.x, nest.z).distance_to(point) < LocationSites.NEST_RADIUS + reach:
			return true
	for ore: Vector3 in location.sites.ore_positions():
		if Vector2(ore.x, ore.z).distance_to(point) < LocationSites.ORE_RADIUS + reach:
			return true
	return false


## The nests `area` holds (each knows its area), all of them inside it.
func _nests_in(location: GeneratedLocation, area: LocationLayout.Area) -> int:
	var nests: int = 0
	for nest: LocationSites.NestSite in location.sites.nests:
		if nest.area == area:
			var at := Vector2(nest.position.x, nest.position.z)
			assert_lt(at.distance_to(area.center), area.radius * 1.3, "inside its area")
			nests += 1
	return nests
