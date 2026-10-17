extends GutTest
## The ship's heat shield: which bodies it reaches, paying its plates (hauls while it's the ship's
## project, the hold) and installing them (see `HeatShield`, `Ship.store_haul`).

const TEST_MAP := preload("res://tests/support/test_map.gd")
const SYSTEM: StarSystem = preload("res://game/world/star_system.tres")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")

var _shield: HeatShield


func before_each() -> void:
	_shield = HeatShield.new()
	watch_signals(_shield)


func test_one_plate_per_planet_inwards() -> void:
	var tiers: Array[int] = []
	for body: CelestialBody in SYSTEM.bodies:
		if body.tier not in tiers:
			tiers.append(body.tier)
	var innermost: int = tiers.max()
	assert_eq(_shield.max_mk(), innermost, "the last plate reaches the innermost tier")
	assert_eq(_shield.mk, 1, "the bare core")
	for level: int in range(2, _shield.max_mk() + 1):
		var plate: ShieldPlate = _shield.plate_for(level)
		assert_not_null(plate, "MK%d" % level)
		assert_gt(plate.cost.size(), 0)
		# Paid mostly with the signature ore of the planet before it.
		var signature: Array[OreType] = []
		for body: CelestialBody in SYSTEM.bodies:
			if body.tier == level - 1:
				signature.append_array(body.signature_ores)
		var has_signature: bool = plate.cost.keys().any(
			func(ore_type: OreType) -> bool: return ore_type in signature
		)
		assert_true(has_signature, "MK%d costs a signature ore of tier %d" % [level, level - 1])
	assert_null(_shield.plate_for(1))
	assert_null(_shield.plate_for(_shield.max_mk() + 1))


func test_reaches_bodies_up_to_its_level() -> void:
	for body: CelestialBody in SYSTEM.bodies:
		assert_eq(_shield.reaches(body), body.tier == 1, body.display_name)
	_shield.install_next()
	for body: CelestialBody in SYSTEM.bodies:
		assert_eq(_shield.reaches(body), body.tier <= 2, body.display_name)
	assert_signal_emitted_with_parameters(_shield, "level_changed", [2])


func test_paying_bit_by_bit_installs_the_plate() -> void:
	var cost: Dictionary[OreType, int] = _shield.next_plate().cost
	assert_eq(_shield.missing().size(), cost.size())
	var taken: Dictionary[OreType, float] = _shield.take_from({MERIDINE: 200.0, KYRITE: 50.0})
	assert_eq(taken, {MERIDINE: 200.0} as Dictionary[OreType, float], "only what it needs")
	assert_eq(_shield.mk, 1)
	assert_almost_eq(_shield.missing()[MERIDINE], cost[MERIDINE] - 200.0, 0.001)
	taken = _shield.take_from({MERIDINE: 500.0, VYREL: 1000.0})
	assert_almost_eq(taken[MERIDINE], cost[MERIDINE] - 200.0, 0.001, "the rest, not more")
	assert_almost_eq(taken[VYREL], float(cost[VYREL]), 0.001)
	assert_eq(_shield.mk, 2, "installed once paid")
	assert_true(_shield.paid.is_empty(), "the next plate starts at nothing")


func test_project_ends_with_its_plate() -> void:
	assert_true(_shield.set_project())
	assert_false(_shield.set_project(), "it already is")
	_shield.take_from({MERIDINE: 9999.0, VYREL: 9999.0})
	assert_false(_shield.project, "the host picks the next one")
	while _shield.install_next():
		pass
	assert_null(_shield.next_plate())
	assert_false(_shield.set_project(), "nothing left to install")
	assert_true(_shield.take_from({MERIDINE: 10.0}).is_empty())


func test_restore_keeps_only_what_fits() -> void:
	_shield.restore(99, true, {})
	assert_eq(_shield.mk, _shield.max_mk(), "clamped")
	assert_false(_shield.project, "nothing left to install")
	var shield := HeatShield.new()
	shield.restore(1, true, {MERIDINE: 9999.0, KYRITE: 20.0})
	assert_eq(shield.paid, {MERIDINE: 300.0} as Dictionary[OreType, float], "only its cost")
	assert_true(shield.project)


func test_haul_pays_the_project_first() -> void:
	var map := TEST_MAP.instantiate() as Node3D
	add_child_autofree(map)
	var ship := map.get_node("Ship") as Ship
	await wait_physics_frames(2)
	# Not the project: everything goes into the hold.
	ship.store_haul({MERIDINE: 100.0})
	assert_eq(ship.hold[MERIDINE], 100.0)
	assert_true(ship.heat_shield.set_project())
	# The example from the design: the plate takes all 200, the next run the last 100.
	ship.store_haul({MERIDINE: 200.0, KYRITE: 40.0})
	assert_eq(ship.hold[MERIDINE], 100.0, "the plate took all of it")
	assert_eq(ship.hold[KYRITE], 40.0, "what it doesn't need is stored")
	ship.store_haul({MERIDINE: 150.0})
	assert_eq(ship.hold[MERIDINE], 150.0, "the last 100 went to the plate")
	assert_eq(ship.heat_shield.paid[MERIDINE], 300.0)
	assert_eq(ship.heat_shield.mk, 1, "still needs Vyrel")


func test_haul_taken_by_the_plate_still_counts_as_found() -> void:
	var map := TEST_MAP.instantiate() as Node3D
	add_child_autofree(map)
	var ship := map.get_node("Ship") as Ship
	await wait_physics_frames(2)
	ship.heat_shield.set_project()
	ship.store_haul({VYREL: 50.0})
	assert_true(ship.found_ores.has(VYREL))


func test_paying_from_the_hold() -> void:
	var map := TEST_MAP.instantiate() as Node3D
	add_child_autofree(map)
	var ship := map.get_node("Ship") as Ship
	await wait_physics_frames(2)
	assert_false(ship.pay_shield(), "nothing in the hold")
	ship.add_to_hold(MERIDINE, 1000.0)
	ship.add_to_hold(VYREL, 100.0)
	assert_true(ship.pay_shield())
	assert_eq(ship.hold[MERIDINE], 700.0)
	assert_eq(ship.hold[VYREL], 0.0, "as far as the hold has it")
	assert_eq(ship.heat_shield.mk, 1)
	ship.add_to_hold(VYREL, 500.0)
	assert_true(ship.pay_shield())
	assert_eq(ship.hold[VYREL], 200.0)
	assert_eq(ship.heat_shield.mk, 2, "installed")
