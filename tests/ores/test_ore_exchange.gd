extends GutTest
## The ore exchange's rules (`OreExchange`): any ore goes in at three for one, common and mid ores
## the hold ever had come out, signature ores never do.

const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")

var _hold: PlayerHold


func before_each() -> void:
	_hold = PlayerHold.new()


func test_three_go_in_for_one_out() -> void:
	_hold.add(KYRITE, 10.0)
	_hold.mark_found(VYREL)
	assert_eq(OreExchange.affordable(KYRITE, _hold), 3)
	assert_true(OreExchange.trade(KYRITE, VYREL, 2, _hold))
	assert_eq(_hold.amount(KYRITE), 4.0)
	assert_eq(_hold.amount(VYREL), 2.0)
	assert_false(OreExchange.trade(KYRITE, VYREL, 2, _hold), "4 pay for one only")
	assert_eq(_hold.amount(KYRITE), 4.0, "nothing taken")
	assert_eq(_hold.amount(VYREL), 2.0)


func test_only_found_common_and_mid_ores_come_out() -> void:
	_hold.add(KYRITE, 30.0)
	_hold.add(MERIDINE, 9.0)
	_hold.mark_found(VYREL)
	var out: Array[OreType] = OreExchange.ores_out(_hold)
	assert_eq(out, [KYRITE, VYREL] as Array[OreType], "found ones, commonest first")
	assert_false(OreExchange.can_take_out(OLVANE, _hold), "never in the hold")
	assert_false(OreExchange.can_take_out(MERIDINE, _hold), "a signature ore")
	assert_false(OreExchange.trade(KYRITE, MERIDINE, 1, _hold))
	assert_false(OreExchange.trade(KYRITE, OLVANE, 1, _hold))


func test_any_ore_with_three_units_goes_in() -> void:
	_hold.add(KYRITE, 2.5)
	_hold.add(MERIDINE, 6.0)
	_hold.add(VYREL, 3.0)
	assert_eq(OreExchange.ores_in(_hold), [VYREL, MERIDINE] as Array[OreType])
	assert_true(OreExchange.trade(MERIDINE, KYRITE, 2, _hold), "a signature ore traded away")
	assert_eq(_hold.amount(MERIDINE), 0.0)
	assert_eq(_hold.amount(KYRITE), 4.5)


func test_not_into_itself_nor_nothing() -> void:
	_hold.add(KYRITE, 9.0)
	assert_false(OreExchange.can_trade(KYRITE, KYRITE, 1, _hold))
	assert_false(OreExchange.can_trade(KYRITE, VYREL, 0, _hold))
	assert_eq(OreExchange.cost(KYRITE, 4), {KYRITE: 12} as Dictionary[ItemType, int])
