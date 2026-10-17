extends GutTest
## How far upgrades go and what their levels cost (see GAME_DESIGN.md, Upgrade stations).

const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")
const SYSTEM: StarSystem = preload("res://game/world/star_system.tres")


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
