extends GutTest
## Which strains hatch where (tiers, the preview in hard regions, biome leanings) and the packs
## they come in (see `AlienHive`, `HatchTable`).

const HIVE: AlienHive = preload("res://game/aliens/hive/hive.tres")
const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const MITE: AlienStrain = preload("res://game/aliens/strains/mite/mite.tres")
const SPITTER: AlienStrain = preload("res://game/aliens/strains/spitter/spitter.tres")
const BURROWER: AlienStrain = preload("res://game/aliens/strains/burrower/burrower.tres")
const WARDEN: AlienStrain = preload("res://game/aliens/strains/warden/warden.tres")
const GNAWER: AlienStrain = preload("res://game/aliens/strains/gnawer/gnawer.tres")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")


func test_the_first_tier_hatches_from_the_start() -> void:
	var table: HatchTable = HIVE.table(1)
	assert_true(table.hatches(SWARMER, 0.0))
	assert_true(table.hatches(MITE, 0.0))
	assert_false(table.hatches(SPITTER, 1.0), "the next tier's don't")
	assert_false(table.hatches(BURROWER, 1.0))


func test_a_tiers_new_strains_come_late_first_then_from_the_start() -> void:
	var first_visit: HatchTable = HIVE.table(2)
	assert_true(first_visit.hatches(SWARMER, 0.0))
	assert_false(first_visit.hatches(SPITTER, 0.0), "not at the start")
	assert_true(first_visit.hatches(SPITTER, HIVE.new_strains_from))
	assert_true(first_visit.hatches(BURROWER, 1.0))
	var next_planet: HatchTable = HIVE.table(3)
	assert_true(next_planet.hatches(SPITTER, 0.0))
	assert_true(next_planet.hatches(BURROWER, 0.0))


func test_hard_regions_preview_one_strain_of_the_next_tier() -> void:
	var table: HatchTable = HIVE.table(1, null, true, 7)
	var previewed: Array[AlienStrain] = []
	for strain: AlienStrain in [SPITTER, BURROWER]:
		if table.hatches(strain, 1.0):
			previewed.append(strain)
			assert_false(table.hatches(strain, HIVE.preview_from - 0.01), "late in the run")
	assert_eq(previewed.size(), 1)
	var again: HatchTable = HIVE.table(1, null, true, 7)
	assert_true(again.hatches(previewed[0], 1.0), "the same location keeps it")


func test_packs_only_with_strains_that_hatch() -> void:
	for pack: AlienPack in HIVE.table(1).packs_at(1.0):
		for strain: AlienStrain in pack.members:
			assert_true(strain.tier == 1, "%s on tier 1" % strain.display_name)
	var late: Array[AlienPack] = HIVE.table(2).packs_at(1.0)
	assert_gt(late.size(), HIVE.table(2).packs_at(0.0).size(), "the new strains' packs join late")


func test_every_hunter_hatches_in_some_pack_and_mites_come_many() -> void:
	for strain: AlienStrain in HIVE.strains:
		if strain.role != Alien.Role.HUNTER:
			continue
		var in_pack: bool = HIVE.packs.any(
			func(pack: AlienPack) -> bool: return pack.members.has(strain)
		)
		assert_true(in_pack, strain.display_name)
	for pack: AlienPack in HIVE.packs:
		if pack.members.has(MITE):
			var mites: int = pack.members[MITE]
			assert_between(mites, 6, 10, "mites in packs of 6 to 10")


func test_biome_leanings_favor_but_never_require() -> void:
	assert_has(DUST.favored_strains, BURROWER)
	var plain: HatchTable = HIVE.table(3)
	var dust: HatchTable = HIVE.table(3, DUST)
	var share_plain: float = _burrower_share(plain)
	var share_dust: float = _burrower_share(dust)
	assert_gt(share_dust, share_plain)
	assert_lt(share_dust, 1.0, "others still come")


func test_guards_and_raiders_are_their_own_strains() -> void:
	assert_eq(WARDEN.role, Alien.Role.GUARD)
	assert_eq(GNAWER.role, Alien.Role.RAIDER)
	var table: HatchTable = HIVE.table(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i: int in 20:
		assert_eq(table.pick_single(rng, 1.0, Alien.Role.GUARD), WARDEN)
		assert_eq(table.pick_single(rng, 1.0, Alien.Role.RAIDER), GNAWER)
	for pack: AlienPack in HIVE.packs:
		for strain: AlienStrain in pack.members:
			assert_eq(strain.role, Alien.Role.HUNTER, "packs are hunters: %s" % strain.display_name)


func test_pack_cap_load_counts_shares() -> void:
	var pack := AlienPack.new()
	pack.members = {SWARMER: 1, MITE: 6}
	assert_eq(pack.aliens().size(), 7)
	assert_almost_eq(pack.cap_load(), 1.0 + 6.0 * MITE.cap_share, 1e-4)


## The share of pack weight that includes a burrower.
func _burrower_share(table: HatchTable) -> float:
	var total: float = 0.0
	var with_burrower: float = 0.0
	for pack: AlienPack in table.packs_at(1.0):
		total += table.weight_of(pack)
		if pack.members.has(BURROWER):
			with_burrower += table.weight_of(pack)
	return with_burrower / total
