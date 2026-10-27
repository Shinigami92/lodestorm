extends GutTest
## How far upgrades go and what their levels cost (see docs/design/progression.md, Upgrade
## stations).

const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")
const SYSTEM: StarSystem = preload("res://game/world/star_system.tres")
const MERISK: AlloyType = preload("res://game/refinery/alloys/alloy_merisk.tres")
## The alloy bars of MK4 to MK8 at scale 1 (TBD (playtest)).
const BARS: Array[int] = [4, 6, 8, 10, 12]
## Their alloys' tiers.
const TIERS: Array[int] = [2, 2, 3, 3, 4]


func test_each_level_costs_a_common_a_mid_and_its_planets_signature_ore() -> void:
	var costs: MkCosts = Upgrade.COSTS
	assert_eq(costs.levels.size() + 1, CelestialBody.MK_ABOVE_TIER + _highest_tier())
	var previous: MkCost = null
	for i: int in costs.levels.size():
		var mk: int = i + 2
		var level: MkCost = costs.levels[i]
		assert_eq(level.common.band, OreType.Band.COMMON, "MK%d" % mk)
		assert_eq(level.mid.band, OreType.Band.MID, "MK%d" % mk)
		if mk < 3:
			assert_null(level.signature, "MK2 needs no signature ore")
		else:
			# The level comes with the planet of tier mk - 2, and so does its ore.
			var bodies: Array[CelestialBody] = []
			for body: CelestialBody in SYSTEM.bodies:
				if body.max_mk() == mk and level.signature in body.signature_ores:
					bodies.append(body)
			assert_false(bodies.is_empty(), "MK%d: the signature ore of its planet" % mk)
		if previous:
			assert_gte(level.common.tier, previous.common.tier, "rarer or the same")
			assert_gte(level.mid.tier, previous.mid.tier, "rarer or the same")
			assert_gt(level.common_amount, previous.common_amount, "MK%d costs more" % mk)
			assert_gt(level.mid_amount, previous.mid_amount)
			if previous.signature:
				assert_gt(level.signature_amount, previous.signature_amount)
		previous = level


## From MK4 on a level also takes the alloy of the previous level's signature ore (refined before
## the level opens), tier 2 for MK4–5, 3 for MK6–7, 4 for MK8, more bars each level.
func test_from_mk4_a_level_takes_the_previous_planets_alloy() -> void:
	var costs: MkCosts = Upgrade.COSTS
	for i: int in costs.levels.size():
		var mk: int = i + 2
		var level: MkCost = costs.levels[i]
		if mk < 4:
			assert_null(level.alloy, "MK%d: ores only" % mk)
			continue
		var before: OreType = costs.levels[i - 1].signature
		assert_true(level.alloy.recipe.has(before), "MK%d: made of %s" % [mk, before.display_name])
		assert_eq(level.alloy.tier, TIERS[mk - 4], "MK%d" % mk)
		assert_eq(level.alloy_bars, BARS[mk - 4], "MK%d" % mk)


func test_alloy_bars_scale_to_whole_bars() -> void:
	assert_eq(Upgrade.COSTS.cost_of(4)[MERISK], 4)
	assert_eq(Upgrade.COSTS.cost_of(4, 0.6)[MERISK], 2, "2.4 rounds to 2")
	assert_eq(Upgrade.COSTS.cost_of(4, 0.05)[MERISK], 1, "at least one")
	assert_eq(ARMOR.cost_of(4)[MERISK], roundi(4 * ARMOR.cost_scale))


func test_the_heat_shield_raises_the_highest_level() -> void:
	var shield := HeatShield.new()
	assert_eq(shield.upgrade_cap(), 3, "MK3 while only Torvane is open")
	assert_true(shield.install_next())
	assert_eq(shield.upgrade_cap(), 4, "MK4 with Vehra")
	while shield.install_next():
		pass
	assert_eq(shield.upgrade_cap(), ARMOR.max_mk(), "every level with every plate")
	for body: CelestialBody in SYSTEM.bodies:
		assert_eq(body.max_mk(), body.tier + 2, body.display_name)


func test_long_pip_rows_keep_their_length() -> void:
	var pips := MkPips.new()
	pips.show_level(1, 3)
	var length: float = _row_length(pips)
	pips.show_level(2, 8)
	assert_eq(pips.get_child_count(), 8)
	assert_almost_eq(_row_length(pips), length, 0.0001, "squeezed into the length of three")
	assert_eq(pips.lit_count(), 2)
	var first := pips.get_child(0) as Node3D
	var second_row := pips.get_child(4) as Node3D
	assert_almost_eq(second_row.position.x, first.position.x, 0.0001, "two rows of four")
	assert_gt(second_row.position.z, first.position.z)
	pips.free()


func _row_length(pips: MkPips) -> float:
	var low: float = INF
	var high: float = -INF
	for pip: MeshInstance3D in pips.get_children():
		var half: float = (pip.mesh as BoxMesh).size.x * 0.5
		low = minf(low, pip.position.x - half)
		high = maxf(high, pip.position.x + half)
	return high - low


func _highest_tier() -> int:
	var highest: int = 1
	for body: CelestialBody in SYSTEM.bodies:
		highest = maxi(highest, body.tier)
	return highest
