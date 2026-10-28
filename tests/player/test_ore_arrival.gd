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
		_player.cargo.add(KYRITE, 1.0)
		_player.cargo.add(OLVANE, 0.5)
		await wait_seconds(1.0 / 30.0)
	assert_false(_arrival.rising, "still arriving")
	assert_ne(_arrival.shown_text(KYRITE), "")
	await wait_seconds(OreArrival.SETTLE_TIME * 3.0)
	assert_true(_arrival.rising, "done")
	assert_eq(_arrival.shown_text(KYRITE), "+30")
	assert_eq(_arrival.shown_text(OLVANE), "+15", "several ores in one line")
	await wait_seconds(OreArrival.RISE_TIME)
	assert_eq(_arrival.shown_text(KYRITE), "", "gone")


func test_a_hose_shows_from_the_first_unit() -> void:
	_player.cargo.add(KYRITE, 1.0)
	await _settle_frames()
	assert_eq(_arrival.shown_text(KYRITE), "+1")


func test_a_trickle_shows_once_it_adds_up() -> void:
	await _trickle(KYRITE, OreArrival.MIN_AMOUNT * 0.5)
	assert_eq(_arrival.shown_text(KYRITE), "", "too little to show")
	await _trickle(KYRITE, OreArrival.MIN_AMOUNT * 0.6)
	assert_ne(_arrival.shown_text(KYRITE), "")


func test_a_trickle_that_stops_is_forgotten() -> void:
	await _trickle(KYRITE, OreArrival.MIN_AMOUNT * 0.5)
	await wait_seconds(OreArrival.SETTLE_TIME * 2.0)
	await _trickle(KYRITE, OreArrival.MIN_AMOUNT * 0.6)
	assert_eq(_arrival.shown_text(KYRITE), "", "starts over")


func test_a_hose_starts_over_a_trickle() -> void:
	# The rest of one miner, then another miner's hose with another ore.
	await _trickle(KYRITE, OreArrival.MIN_AMOUNT * 0.5)
	_player.cargo.add(OLVANE, 3.0)
	await _settle_frames()
	assert_eq(_arrival.shown_text(KYRITE), "", "not part of the line")
	assert_eq(_arrival.shown_text(OLVANE), "+3")


func test_spending_ore_shows_nothing() -> void:
	_player.cargo.add(KYRITE, 50.0)
	await wait_seconds(OreArrival.SETTLE_TIME * 2.0 + OreArrival.RISE_TIME)
	_player.cargo.take(KYRITE, 20.0)
	await wait_process_frames(2)
	assert_eq(_arrival.shown_text(KYRITE), "")


func test_dying_clears_it() -> void:
	_player.cargo.add(KYRITE, 50.0)
	await wait_process_frames(2)
	_player.take_damage(_player.max_health())
	await wait_process_frames(1)
	assert_eq(_arrival.shown_text(KYRITE), "")


## Ore coming in `units` at a trickle (slower than a hose), one bit per physics step.
func _trickle(ore_type: OreType, units: float) -> void:
	var step: float = OreArrival.SETTLE_RATE * 0.4 * get_physics_process_delta_time()
	var left: float = units
	while left > 0.0:
		_player.cargo.add(ore_type, minf(step, left))
		left -= step
		await wait_physics_frames(1)
	await _settle_frames()


## Lets the physics step take in what arrived and the next frame show it.
func _settle_frames() -> void:
	await wait_physics_frames(2)
	await wait_process_frames(1)
