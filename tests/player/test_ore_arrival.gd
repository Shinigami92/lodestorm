extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")

var _player: Player
var _arrival: OreArrival


func before_each() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_arrival = _player.get_node("OreArrival") as OreArrival
	add_child_autofree(_player)
	await wait_process_frames(1)


func test_a_delivery_counts_up_then_rises() -> void:
	# A hose at 30 units a second for a second.
	for i: int in 30:
		_player.add_cargo(KYRITE, 1.0)
		_player.add_cargo(OLVANE, 0.5)
		await wait_seconds(1.0 / 30.0)
	assert_false(_arrival.rising, "still arriving")
	assert_ne(_arrival.shown_text(KYRITE), "")
	await wait_seconds(OreArrival.RATE_TIME * 3.0)
	assert_true(_arrival.rising, "done")
	assert_eq(_arrival.shown_text(KYRITE), "+30")
	assert_eq(_arrival.shown_text(OLVANE), "+15", "several ores in one line")
	await wait_seconds(OreArrival.RISE_TIME)
	assert_eq(_arrival.shown_text(KYRITE), "", "gone")


func test_a_trickle_shows_once_it_adds_up() -> void:
	_player.add_cargo(KYRITE, OreArrival.MIN_AMOUNT * 0.5)
	await wait_process_frames(2)
	assert_eq(_arrival.shown_text(KYRITE), "", "too little to show")
	_player.add_cargo(KYRITE, OreArrival.MIN_AMOUNT * 0.5)
	await wait_process_frames(2)
	assert_eq(_arrival.shown_text(KYRITE), "+%d" % OreArrival.MIN_AMOUNT)


func test_spending_ore_shows_nothing() -> void:
	_player.add_cargo(KYRITE, 50.0)
	# All at once: the rate takes a while to settle.
	await wait_seconds(OreArrival.RATE_TIME * 6.0 + OreArrival.RISE_TIME)
	_player.take_ore(KYRITE, 20.0)
	await wait_process_frames(2)
	assert_eq(_arrival.shown_text(KYRITE), "")


func test_dying_clears_it() -> void:
	_player.add_cargo(KYRITE, 50.0)
	await wait_process_frames(2)
	_player.take_damage(_player.max_health())
	await wait_process_frames(1)
	assert_eq(_arrival.shown_text(KYRITE), "")
