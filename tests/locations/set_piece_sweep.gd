extends RefCounted
## The sweep over every region's set pieces, the slowest test: split into `PARTS` scripts
## (`test_set_pieces_<part>.gd`), which run in parallel, each planning its share of the locations.

const SWEEP := preload("res://tests/support/location_sweep.gd")
const STAR_SYSTEM: StarSystem = preload("res://game/world/star_system.tres")
## How many scripts share the sweep.
const PARTS: int = 3
## Seeds per region.
const SEEDS: int = 2


## Every region's set pieces are in every section of it; the parts stand on reachable ground that
## kept every step, their markers (crates, ore, quest sites) too, and nobody gets stuck. Regions
## with the same biome and set pieces plan the same, so each pair is swept once. Checks the
## `part`th (from 1) of `PARTS` shares of the planned locations.
static func check(test: GutTest, part: int) -> void:
	var scripts: int = 0
	for file: String in DirAccess.get_files_at("res://tests/locations/"):
		if file.begins_with("test_set_pieces_") and file.ends_with(".gd"):
			scripts += 1
	test.assert_eq(scripts, PARTS, "a script per part")
	var regions: Array[Region] = []
	var swept: Array[String] = []
	for body: CelestialBody in STAR_SYSTEM.bodies:
		for region: Region in body.regions:
			var key: String = region.biome.resource_path
			for placement: PartPlacement in region.set_pieces:
				key += " %s %d" % [placement.scene.resource_path, placement.rule]
			if key not in swept:
				swept.append(key)
				regions.append(region)
	var index: int = 0
	for region: Region in regions:
		for world_seed: int in SWEEP.seeds(region.biome, SEEDS):
			index += 1
			if index % PARTS != part % PARTS:
				continue
			var location: GeneratedLocation = SWEEP.plan(
				world_seed, region.biome, region.set_pieces
			)
			var label: String = "%s seed %d" % [region.display_name, world_seed]
			var set_pieces: Array[PackedScene] = []
			for placed: LocationParts.Placed in location.parts.placed:
				if placed.set_piece:
					set_pieces.append(placed.placement.scene)
				test.assert_ne(placed.area.kind, LocationLayout.Kind.LANDING, label)
				if not placed.set_piece:
					test.assert_ne(placed.area.kind, LocationLayout.Kind.ORE_POCKET, label)
				_assert_part_reachable(test, location, placed, label)
			for placement: PartPlacement in region.set_pieces:
				test.assert_has(set_pieces, placement.scene, label)
			test.assert_eq(location.stuck_spots(), PackedVector2Array(), label)
			location.free()


static func _assert_part_reachable(
	test: GutTest, location: GeneratedLocation, part: LocationParts.Placed, label: String
) -> void:
	var part_label: String = "%s: %s" % [label, part.info.display_name]
	var center := Vector2(part.origin.x, part.origin.z)
	test.assert_almost_eq(
		part.origin.y, location.terrain.height_at(center.x, center.y), 0.01, part_label
	)
	# The ring around the props, all the way round.
	var ring: float = (part.info.prop_radius + part.info.footprint) * 0.5
	for step: int in 16:
		var at: Vector2 = center + Vector2.from_angle(step * TAU / 16.0) * ring
		test.assert_true(location.is_reachable(at.x, at.y), part_label + " ring")
	for i: int in part.info.marker_spots.size():
		var at: Vector3 = part.marker_position(i)
		test.assert_true(location.is_reachable(at.x, at.z), part_label + " marker")
