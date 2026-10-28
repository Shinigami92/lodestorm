extends GutTest

const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")

var _cargo: PlayerCargo


func before_each() -> void:
	_cargo = PlayerCargo.new()
	watch_signals(_cargo)


func test_adds_up_per_ore_type() -> void:
	_cargo.add(KYRITE, 10.0)
	_cargo.add(KYRITE, 5.0)
	_cargo.add(OLVANE, 2.0)
	assert_eq(_cargo.amount(KYRITE), 15.0)
	assert_eq(_cargo.total(), 17.0)
	assert_signal_emitted_with_parameters(_cargo, "ore_changed", [KYRITE, 15.0], 1)
	assert_signal_emitted_with_parameters(_cargo, "ore_added", [KYRITE, 5.0], 1)


func test_nothing_added_emits_nothing() -> void:
	_cargo.add(KYRITE, 0.0)
	assert_true(_cargo.is_empty())
	assert_signal_not_emitted(_cargo, "ore_added")


func test_takes_at_most_what_it_carries() -> void:
	_cargo.add(KYRITE, 10.0)
	assert_eq(_cargo.take(KYRITE, 4.0), 4.0)
	assert_eq(_cargo.take(KYRITE, 100.0), 6.0)
	assert_eq(_cargo.take(OLVANE, 1.0), 0.0, "none carried")
	assert_true(_cargo.is_empty())


func test_take_all_empties_it() -> void:
	_cargo.add(KYRITE, 10.0)
	_cargo.add(OLVANE, 2.0)
	var taken: Dictionary[OreType, float] = _cargo.take_all()
	assert_eq(taken, {KYRITE: 10.0, OLVANE: 2.0})
	assert_true(_cargo.ores.is_empty())
	assert_signal_emitted_with_parameters(_cargo, "ore_changed", [OLVANE, 0.0])
