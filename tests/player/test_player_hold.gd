extends GutTest
## Every player's own hold (`PlayerHold`): amounts per item, what was ever in it, paying, and every
## run's haul going whole to every player in the session (`Ship.store_haul`).

const TEST_MAP := preload("res://tests/support/test_map.gd")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")


func test_adds_takes_and_pays() -> void:
	var hold := PlayerHold.new()
	watch_signals(hold)
	assert_eq(hold.amount(KYRITE), 0.0)
	hold.add(KYRITE, 120.0)
	assert_eq(hold.amount(KYRITE), 120.0)
	assert_signal_emitted_with_parameters(hold, "item_changed", [KYRITE, 120.0])
	assert_eq(hold.take(KYRITE, 200.0), 120.0, "at most what it has")
	assert_eq(hold.amount(KYRITE), 0.0)
	hold.add(KYRITE, 100.0)
	assert_false(hold.can_pay({KYRITE: 50, OLVANE: 1}), "no Olvane")
	assert_false(hold.pay({KYRITE: 50, OLVANE: 1}))
	assert_eq(hold.amount(KYRITE), 100.0, "nothing taken")
	assert_true(hold.pay({KYRITE: 50}))
	assert_eq(hold.amount(KYRITE), 50.0)


func test_remembers_what_was_ever_in_it() -> void:
	var hold := PlayerHold.new()
	assert_false(hold.has_found(KYRITE))
	hold.add(KYRITE, 10.0)
	assert_true(hold.pay({KYRITE: 10}))
	assert_true(hold.has_found(KYRITE), "stays found once spent")
	hold.mark_found(MERIDINE)
	assert_true(hold.has_found(MERIDINE))
	assert_eq(hold.amount(MERIDINE), 0.0)


func test_ores_lists_the_ores() -> void:
	var hold := PlayerHold.new()
	hold.add(KYRITE, 5.0)
	hold.add(OLVANE, 7.0)
	assert_eq(hold.ores(), {KYRITE: 5.0, OLVANE: 7.0} as Dictionary[OreType, float])


## Nothing is split: everyone in the session gets the whole haul into their own hold.
func test_every_player_gets_the_whole_haul() -> void:
	var map := TEST_MAP.instantiate() as Node3D
	add_child_autofree(map)
	var ship := map.get_node("Ship") as Ship
	var player := map.get_node("Player") as Player
	var other: Player = PLAYER_SCENE.instantiate() as Player
	other.local = false
	map.add_child(other)
	await wait_physics_frames(2)
	other.hold.add(KYRITE, 30.0)
	ship.store_haul({KYRITE: 100.0, MERIDINE: 40.0}, [player, other])
	assert_eq(player.hold.amount(KYRITE), 100.0)
	assert_eq(player.hold.amount(MERIDINE), 40.0)
	assert_eq(other.hold.amount(KYRITE), 130.0, "added to what it had")
	assert_eq(other.hold.amount(MERIDINE), 40.0)
