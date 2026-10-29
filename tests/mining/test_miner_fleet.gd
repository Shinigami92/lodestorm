extends GutTest
## A player's crafted miners and the standard-issue ones filling up a run (`MinerFleet`), one per
## open cradle of the ship (`Cradles`).

const FULL_HOLD := preload("res://tests/support/full_hold.gd")
const TANK: Upgrade = preload("res://game/progression/upgrades/miner_tank.tres")
const PLATING: Upgrade = preload("res://game/progression/upgrades/miner_plating.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")

var _fleet: MinerFleet
var _hold: PlayerHold


func before_each() -> void:
	_fleet = MinerFleet.new()
	_hold = FULL_HOLD.fill()


func test_every_player_starts_with_m01() -> void:
	var first: CraftedMiner = _fleet.get_miner(1)
	assert_not_null(first)
	assert_true(first.is_built())
	assert_true(first.going_along)
	assert_eq(first.plate(), "M-01")
	for number: int in range(2, MinerFleet.SLOTS + 1):
		assert_true(_fleet.is_empty(number), "cradle %d" % number)
	assert_eq(_fleet.per_run(), Cradles.START, "two cradles open")
	assert_eq(_fleet.standard_count(), 1)
	assert_eq(_fleet.left_to_place(), 2)


func test_open_cradles_set_the_run() -> void:
	assert_false(_fleet.start_build(3, _settings(10), _hold, 0.0), "no cradle there")
	_fleet.build_all()
	assert_true(_fleet.is_empty(3), "only the open ones")
	assert_eq(_fleet.standard_count(), 0)
	watch_signals(_fleet)
	assert_true(_fleet.cradles.open_next())
	assert_signal_emitted(_fleet, "changed")
	assert_eq(_fleet.left_to_place(), 3, "one more standard-issue miner")
	assert_true(_fleet.start_build(3, _settings(10), _hold, 0.0))


func test_a_run_takes_the_first_crafted_miners_up_to_the_open_cradles() -> void:
	_fleet.cradles.restore(MinerFleet.SLOTS)
	_fleet.build_all()
	_fleet.cradles.restore(3)
	assert_eq(_fleet.along().size(), 3, "the others stay home")
	assert_eq(_fleet.along()[2].number, 3, "by number")
	assert_eq(_fleet.standard_count(), 0)
	assert_eq(_fleet.left_to_place(), 3)
	assert_not_null(_fleet.get_miner(6), "never lost")


func test_crafted_miners_going_along_and_standard_issue_fill_a_run() -> void:
	_fleet.cradles.restore(MinerFleet.SLOTS)
	_fleet.build_all()
	_fleet.get_miner(2).going_along = false
	assert_eq(_fleet.standard_count(), 1, "five crafted ones go along")
	var numbers: Array[int] = []
	for miner: CraftedMiner in _fleet.waiting():
		numbers.append(miner.number)
	assert_eq(numbers, [1, 3, 4, 5, 6] as Array[int], "by number")
	_fleet.take(_fleet.get_miner(4))
	_fleet.take(null)
	assert_eq(_fleet.waiting().size(), 4)
	assert_eq(_fleet.standard_left(), 0)
	assert_eq(_fleet.left_to_place(), 4)


func test_picked_up_miners_can_be_placed_again() -> void:
	var first: CraftedMiner = _fleet.get_miner(1)
	_fleet.take(first)
	_fleet.take(null)
	assert_eq(_fleet.left_to_place(), 0)
	_fleet.bring_back(first)
	_fleet.bring_back(null)
	assert_eq(_fleet.left_to_place(), 2)
	assert_eq(_fleet.waiting(), [first] as Array[CraftedMiner])


func test_miners_left_on_the_planet_are_lost() -> void:
	_fleet.build_all()
	var first: CraftedMiner = _fleet.get_miner(1)
	var second: CraftedMiner = _fleet.get_miner(2)
	_fleet.take(first)
	_fleet.take(second)
	_fleet.bring_back(second)
	first.upgrades.start(TANK, _hold, 0.0)
	var lost: Array[int] = _fleet.end_run("Torvane, Redscar Flats")
	assert_eq(lost, [1] as Array[int])
	assert_true(_fleet.is_empty(1), "with its level under way")
	assert_eq(_fleet.lost_at[1], "Torvane, Redscar Flats")
	assert_not_null(_fleet.get_miner(2), "picked up in time")
	assert_false(_fleet.get_miner(2).out)


func test_standard_issue_miners_are_never_lost() -> void:
	_fleet.get_miner(1).going_along = false
	assert_true(_fleet.waiting().is_empty())
	for i: int in _fleet.per_run():
		_fleet.take(null)
	assert_eq(_fleet.left_to_place(), 0)
	assert_eq(_fleet.end_run("there"), [] as Array[int])
	assert_eq(_fleet.left_to_place(), _fleet.per_run(), "refilled for the next run")
	assert_not_null(_fleet.get_miner(1))


func test_damage_comes_along_until_the_run_ends() -> void:
	var first: CraftedMiner = _fleet.get_miner(1)
	_fleet.take(first)
	first.health = 40.0
	_fleet.bring_back(first)
	assert_eq(first.health, 40.0)
	_fleet.end_run("there")
	assert_eq(first.health, -1.0, "repaired aboard")


func test_building_runs_on_the_wall_clock() -> void:
	_fleet.cradles.restore(MinerFleet.SLOTS)
	assert_true(_fleet.start_build(3, _settings(180), _hold, 1000.0))
	assert_false(_fleet.start_build(3, _settings(180), _hold, 1000.0), "one per cradle")
	assert_false(_fleet.start_build(1, _settings(180), _hold, 1000.0), "M-01 is there")
	var building: CraftedMiner = _fleet.get_miner(3)
	assert_false(building.is_built())
	assert_false(building in _fleet.along(), "not before it's built")
	assert_eq(_fleet.update(1100.0), [] as Array[Resource])
	assert_eq(_fleet.update(1180.0), [building] as Array[Resource])
	assert_true(building.is_built())
	assert_true(building in _fleet.along())


func test_building_again_clears_where_it_was_lost() -> void:
	_fleet.take(_fleet.get_miner(1))
	_fleet.end_run("there")
	assert_true(_fleet.start_build(1, _settings(10), _hold, 0.0))
	assert_false(_fleet.lost_at.has(1))


func test_a_build_is_paid_and_given_back_when_stopped() -> void:
	var hold := PlayerHold.new()
	var settings: MinerSettings = _settings(180)
	settings.build_cost = {KYRITE: 40}
	assert_false(_fleet.start_build(2, settings, hold, 0.0), "an empty hold")
	hold.add(KYRITE, 50.0)
	assert_true(_fleet.start_build(2, settings, hold, 0.0))
	assert_eq(hold.amount(KYRITE), 10.0, "paid")
	assert_false(_fleet.stop_build(1, hold), "M-01 is built")
	assert_true(_fleet.stop_build(2, hold))
	assert_true(_fleet.is_empty(2))
	assert_eq(hold.amount(KYRITE), 50.0, "the whole cost back")


func test_part_levels_finish_with_the_fleet() -> void:
	var first: CraftedMiner = _fleet.get_miner(1)
	first.upgrades.start(PLATING, _hold, 0.0)
	assert_eq(_fleet.update(1.0e9), [PLATING] as Array[Resource])
	assert_eq(first.upgrades.mk(PLATING), 2)


func test_finish_all_builds_and_levels() -> void:
	_fleet.cradles.restore(MinerFleet.SLOTS)
	_fleet.start_build(4, _settings(1_000_000_000), _hold, 0.0)
	_fleet.get_miner(1).upgrades.start(TANK, _hold, 0.0)
	assert_eq(_fleet.finish_all().size(), 2)
	assert_true(_fleet.get_miner(4).is_built())
	assert_eq(_fleet.get_miner(1).upgrades.mk(TANK), 2)


func test_changes_are_announced() -> void:
	watch_signals(_fleet)
	_fleet.get_miner(1).upgrades.raise(TANK)
	assert_signal_emitted(_fleet, "changed", "a miner's levels")


## Settings whose build takes `seconds` and costs nothing.
func _settings(seconds: int) -> MinerSettings:
	var settings := MinerSettings.new()
	settings.build_seconds = seconds
	return settings
