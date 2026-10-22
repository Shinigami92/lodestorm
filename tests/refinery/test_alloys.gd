extends GutTest
## The alloys (`AlloyCatalog`): eight in four tiers of two, every ore going into one at least, their
## recipes and times, how they become known and their ingot badges.

const CATALOG: AlloyCatalog = preload("res://game/refinery/all_alloys.tres")
const ORES: OreCatalog = preload("res://game/ores/all_ores.tres")
const COBREL: AlloyType = preload("res://game/refinery/alloys/alloy_cobrel.tres")
const MERISK: AlloyType = preload("res://game/refinery/alloys/alloy_merisk.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
## Units of an ore per bar, by its band.
const AMOUNTS: Dictionary[OreType.Band, int] = {
	OreType.Band.COMMON: 10,
	OreType.Band.MID: 5,
	OreType.Band.SIGNATURE: 3,
}


func test_every_alloy_file_is_listed() -> void:
	var dir: String = "res://game/refinery/alloys/"
	var files: PackedStringArray = DirAccess.get_files_at(dir)
	var count: int = 0
	for file: String in files:
		if file.ends_with(".tres"):
			count += 1
			assert_has(CATALOG.alloys, load(dir + file), file)
	assert_eq(count, CATALOG.alloys.size())


func test_two_alloys_per_tier_in_order() -> void:
	assert_eq(CATALOG.alloys.size(), 8)
	for index: int in CATALOG.alloys.size():
		@warning_ignore("integer_division")
		assert_eq(CATALOG.alloys[index].tier, index / 2 + 1, CATALOG.alloys[index].display_name)


func test_recipes_take_a_common_a_mid_and_from_tier_2_a_signature_ore() -> void:
	for alloy: AlloyType in CATALOG.alloys:
		var bands: Array[OreType.Band] = []
		for ore_type: OreType in alloy.recipe:
			bands.append(ore_type.band)
			assert_eq(alloy.recipe[ore_type], AMOUNTS[ore_type.band], alloy.display_name)
		var expected: Array[OreType.Band] = [OreType.Band.COMMON, OreType.Band.MID]
		if alloy.tier >= 2:
			expected.append(OreType.Band.SIGNATURE)
		assert_eq(bands, expected, alloy.display_name)


func test_every_ore_goes_into_an_alloy() -> void:
	for ore_type: OreType in ORES.ores:
		var uses: int = 0
		for alloy: AlloyType in CATALOG.alloys:
			if ore_type in alloy.recipe:
				uses += 1
		var needed: int = 1 if ore_type.band == OreType.Band.SIGNATURE else 2
		assert_eq(uses, needed, ore_type.display_name)


func test_names_start_with_their_own_letter() -> void:
	var letters: Dictionary[String, AlloyType] = {}
	for alloy: AlloyType in CATALOG.alloys:
		var letter: String = alloy.display_name.left(1)
		assert_false(letters.has(letter), "%s and another alloy" % alloy.display_name)
		letters[letter] = alloy


func test_higher_tiers_take_longer() -> void:
	for alloy: AlloyType in CATALOG.alloys:
		for other: AlloyType in CATALOG.alloys:
			if other.tier > alloy.tier:
				assert_gt(other.seconds_per_bar, alloy.seconds_per_bar, other.display_name)


func test_cost_and_what_the_hold_pays_for() -> void:
	assert_eq(COBREL.cost(3), {KYRITE: 30, VYREL: 15} as Dictionary[ItemType, int])
	var hold := PlayerHold.new()
	assert_eq(COBREL.affordable(hold), 0)
	hold.add(KYRITE, 45.0)
	hold.add(VYREL, 100.0)
	assert_eq(COBREL.affordable(hold), 4, "the kyrite runs out first")


func test_known_once_every_ore_was_in_the_hold() -> void:
	var hold := PlayerHold.new()
	assert_false(COBREL.is_known(hold))
	hold.add(KYRITE, 5.0)
	assert_false(COBREL.is_known(hold))
	assert_eq(COBREL.found_ores(hold), [KYRITE] as Array[OreType])
	hold.mark_found(VYREL)
	assert_true(COBREL.is_known(hold))
	assert_true(hold.pay({KYRITE: 5}))
	assert_true(COBREL.is_known(hold), "stays known once spent")


func test_badges_are_ingots_with_a_tick_per_tier() -> void:
	var cobrel: Texture2D = COBREL.get_badge_icon()
	var merisk: Texture2D = MERISK.get_badge_icon()
	assert_not_null(cobrel)
	assert_ne(cobrel, merisk, "an icon per tier")
	assert_eq(COBREL.get_badge_icon(), cobrel, "drawn once")
	assert_ne(cobrel, ItemBadge.fallback_icon(), "not the ores' crystal")
	# Along the front face's middle: one tick for tier 1, two for tier 2.
	assert_eq(_ticks(1), 1)
	assert_eq(_ticks(2), 2)
	assert_eq(_ticks(4), 4)
	var badge := ItemBadge.new(COBREL)
	add_child_autofree(badge)
	assert_eq(badge.get_icon_texture(), cobrel)
	assert_eq(badge.get_shown_name(), "Cobrel")


## The ticks found along the ingot's front face at the ticks' height.
func _ticks(tier: int) -> int:
	var ticks: int = 0
	var on_tick: bool = false
	for step: int in 200:
		var x: float = -1.0 + step / 100.0
		var shade: float = IngotIcon.shade_at(Vector2(x, 0.2), tier)
		var is_tick: bool = shade == IngotIcon.TICK_SHADE
		if is_tick and not on_tick:
			ticks += 1
		on_tick = is_tick
	return ticks
