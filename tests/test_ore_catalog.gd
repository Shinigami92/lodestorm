extends GutTest
## Every ore of the game (`OreCatalog`) and where they're found: biomes carry the common and mid
## ores, each planet its signature ore, regions add or drop ores.

const CATALOG: OreCatalog = preload("res://scenes/mining/ores/all_ores.tres")
const SYSTEM: StarSystem = preload("res://scenes/world/star_system.tres")
const ORES_DIR: String = "res://scenes/mining/ores/"
const KYRITE: OreType = preload("res://scenes/mining/ores/ore_kyrite.tres")
const OLVANE: OreType = preload("res://scenes/mining/ores/ore_olvane.tres")
const VYREL: OreType = preload("res://scenes/mining/ores/ore_vyrel.tres")
const MERIDINE: OreType = preload("res://scenes/mining/ores/ore_meridine.tres")
const EMERIN: OreType = preload("res://scenes/mining/ores/ore_emerin.tres")


func test_every_ore_is_in_the_catalog() -> void:
	for file: String in DirAccess.get_files_at(ORES_DIR):
		if file.begins_with("ore_") and file.ends_with(".tres"):
			var ore_type := load(ORES_DIR + file) as OreType
			assert_has(CATALOG.ores, ore_type, file)


func test_catalog_is_ordered_commonest_first() -> void:
	assert_eq(CATALOG.ores, OreCatalog.sorted(CATALOG.ores))
	var tiers: Dictionary[int, bool] = {}
	var initials: Dictionary[String, bool] = {}
	var bands: Array[OreType.Band] = []
	for ore_type: OreType in CATALOG.ores:
		assert_false(tiers.has(ore_type.tier), "%s: own tier" % ore_type.display_name)
		tiers[ore_type.tier] = true
		var initial: String = ore_type.display_name.left(1)
		assert_false(initials.has(initial), "%s: own first letter" % ore_type.display_name)
		initials[initial] = true
		if not bands.is_empty():
			assert_gte(ore_type.band, bands[-1], "%s: bands in order" % ore_type.display_name)
		bands.append(ore_type.band)


func test_rarer_ores_make_more_ammo_and_mine_slower() -> void:
	for ore_type: OreType in CATALOG.ores:
		var label: String = ore_type.display_name
		assert_gte(ore_type.ammo_yield, 1.0, label)
		assert_lte(ore_type.mine_rate, 1.0, label)
		if ore_type.band == OreType.Band.SIGNATURE:
			assert_gt(ore_type.ammo_yield, VYREL.ammo_yield, label)
			assert_lt(ore_type.mine_rate, VYREL.mine_rate, label)


func test_every_ore_has_its_look() -> void:
	for ore_type: OreType in CATALOG.ores:
		var label: String = ore_type.display_name
		assert_not_null(ore_type.model, label + " model")
		assert_eq(ore_type.variants.size(), 2, label + " variants")
		assert_not_null(ore_type.icon, label + " icon")
		for variant: StringName in ore_type.variants:
			assert_not_null(
				ModelParts.mesh(ore_type.model, "Base_" + String(variant).trim_prefix("Ore_")),
				"%s %s" % [label, variant]
			)


func test_region_ores_are_biome_and_signature_ores() -> void:
	var biome := LocationBiome.new()
	biome.ores = [OLVANE, KYRITE] as Array[OreType]
	var body := CelestialBody.new()
	body.signature_ores = [MERIDINE] as Array[OreType]
	var region := Region.new()
	region.biome = biome
	assert_eq(region.ores_on(body), [KYRITE, OLVANE, MERIDINE] as Array[OreType])
	assert_eq(region.ores_on(null), [KYRITE, OLVANE] as Array[OreType], "without a body")
	region.extra_ores = [VYREL] as Array[OreType]
	region.missing_ores = [OLVANE] as Array[OreType]
	assert_eq(region.ores_on(body), [KYRITE, VYREL, MERIDINE] as Array[OreType])


func test_each_region_has_three_to_six_ores() -> void:
	for region: Region in _regions():
		var ores: Array[OreType] = SYSTEM.ores_of(region)
		assert_between(ores.size(), 3, 6, region.display_name)


func test_signature_ores_stay_on_their_planet() -> void:
	for region: Region in _regions():
		var body: CelestialBody = SYSTEM.body_of(region)
		for ore_type: OreType in SYSTEM.ores_of(region):
			if ore_type.band == OreType.Band.SIGNATURE:
				assert_has(body.signature_ores, ore_type, region.display_name)
	var torvane: Region = _region("Redscar Flats")
	assert_has(SYSTEM.ores_of(torvane), MERIDINE)
	assert_does_not_have(SYSTEM.ores_of(torvane), EMERIN)


func test_missions_bring_their_region_ores() -> void:
	var region: Region = _region("Hollow Mire")
	var brief := MissionBrief.for_region(region, 7, SYSTEM.ores_of(region))
	assert_eq(brief.found_ores(), SYSTEM.ores_of(region))
	var bare := MissionBrief.for_region(region, 7)
	assert_eq(bare.found_ores(), OreCatalog.sorted(region.biome.ores), "falls back to the biome's")


func test_old_ore_paths_load_from_saves() -> void:
	for old: String in SaveGame.RENAMED:
		assert_true(ResourceLoader.exists(SaveGame.RENAMED[old]), old)


func _regions() -> Array[Region]:
	var regions: Array[Region] = []
	for body: CelestialBody in SYSTEM.bodies:
		regions.append_array(body.regions)
	return regions


func _region(region_name: String) -> Region:
	for region: Region in _regions():
		if region.display_name == region_name:
			return region
	return null
