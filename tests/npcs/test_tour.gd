extends GutTest
## Brannik's tour (`Tour`, `NpcTour`, `NpcRoutine`): on a new game he waits in front of the cabins
## with the offer; "Later" sends him to the armory, and so does the first destination chosen
## without talking to him (the tour still on offer); "Show me the ship" starts the tour, he waits at
## each stop for the player and says its line; talking to him during it offers going on or ending
## it; a player who walks off ends it; he takes the lift between the decks, and the lift waits for
## him while he steps on.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const QUARTERMASTER: String = "Rooms/Lower/Armory/Quartermaster"

var _map: Node3D
var _ship: Ship
var _player: Player
var _brannik: Npc


func test_a_new_game_starts_with_him_waiting_at_the_cabins() -> void:
	await _load()
	var start := _ship.get_node("Tour/Start") as Node3D
	assert_almost_eq(_brannik.global_position, start.global_position, Vector3.ONE * 0.01)
	assert_true(_brannik.routine.is_waiting())
	assert_true(_brannik.has_news(_player), "the amber marker: something new")
	_brannik.open(_player)
	var tour: Tour = _brannik.profile.tour
	assert_eq(_brannik.talk.topic, tour.offer, "the offer instead of his armory greeting")
	while _brannik.talk.topic:
		_brannik.talk.press()
	assert_eq(
		_brannik.get_choices(), [tour.invite] as Array[Topic], "Show me the ship, then Goodbye"
	)
	_brannik.close()
	assert_false(_brannik.routine.is_waiting(), "Later: he doesn't wait any more")
	await _until(func() -> bool: return _brannik.body.is_walking(), 10.0)
	assert_true(_brannik.body.is_walking(), "on his way to the armory")


func test_the_first_destination_chosen_sends_him_to_the_armory() -> void:
	await _load()
	assert_true(_brannik.routine.is_waiting())
	var voyage: Voyage = _ship.voyage
	assert_true(voyage.choose(voyage.offers[0]), "Set as destination at the navigator")
	assert_false(_brannik.routine.is_waiting(), "he doesn't wait any more")
	await _until(func() -> bool: return _brannik.body.is_walking(), 10.0)
	assert_true(_brannik.body.is_walking(), "on his way to the armory")
	assert_eq(
		_brannik.get_greeting(),
		_brannik.profile.dialogue.greeting,
		"his own greeting, not the offer"
	)
	assert_true(
		_brannik.get_choices(_player).has(_brannik.profile.tour.invite), "the tour still on offer"
	)


func test_once_the_offer_is_heard_he_starts_in_the_armory() -> void:
	await _load([&"quartermaster.tour_offer"])
	assert_false(_brannik.routine.is_waiting())
	var start := _ship.get_node("Tour/Start") as Node3D
	assert_gt(
		_brannik.global_position.distance_to(start.global_position), 10.0, "not at the cabins"
	)
	assert_true(
		_brannik.get_choices(_player).has(_brannik.profile.tour.invite), "the tour any time"
	)


func test_the_tour_waits_for_the_player_at_each_stop() -> void:
	await _load()
	await _start_tour()
	assert_null(_brannik.user, "the talk closes")
	var tour: NpcTour = _brannik.routine.tour
	assert_not_null(tour, "the tour runs")
	assert_eq(tour.stop, 0)
	var stop := tour.get_marker()
	assert_eq(stop.name, &"MessHall")
	# The player stays where they are, out of reach: he walks there and waits.
	await _until(func() -> bool: return not _brannik.routine.is_underway(), 40.0)
	assert_almost_eq(_brannik.global_position, stop.global_position, Vector3.ONE * 0.05)
	await wait_physics_frames(30)
	assert_false(tour.is_talking(), "waits for the player")
	_player.global_position = stop.global_position + stop.global_basis.z * 2.0 + Vector3.UP * 0.1
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_true(tour.is_talking(), "says the stop's line once they're close")
	assert_true(_brannik.bubble.visible, "in the bubble above his head")
	var line: String = tour.tour.stops[0].lines[0]
	assert_eq((_brannik.bubble.content as SpeechBubble).get_line(), line)
	await _until(func() -> bool: return tour.stop == 1, 30.0)
	assert_eq(tour.stop, 1, "then on to the next stop")
	assert_false(_brannik.bubble.visible)


func test_talking_during_the_tour_offers_going_on_or_ending_it() -> void:
	await _load()
	await _start_tour()
	var tour: Tour = _brannik.profile.tour
	await wait_physics_frames(10)
	_player.global_position = _brannik.global_position + Vector3(0.0, 0.1, 1.0)
	_player.reset_physics_interpolation()
	_brannik.open(_player)
	assert_eq(_brannik.get_choices(), [tour.resume, tour.abort] as Array[Topic])
	assert_false(_brannik.body.is_walking(), "stands while they talk")
	_brannik.talk.talk_about(tour.resume)
	while _brannik.talk.topic:
		_brannik.talk.press()
	await wait_physics_frames(2)
	assert_null(_brannik.user, "Go on: the talk closes")
	assert_not_null(_brannik.routine.tour, "and the tour goes on")
	_brannik.open(_player)
	_brannik.talk.talk_about(tour.abort)
	while _brannik.talk.topic:
		_brannik.talk.press()
	await wait_physics_frames(2)
	assert_null(_brannik.user)
	assert_null(_brannik.routine.tour, "End the tour")
	assert_true(_brannik.get_choices(_player).has(tour.invite), "it can be asked for again")


func test_a_player_who_walks_off_ends_it() -> void:
	await _load()
	await _start_tour()
	_player.global_position = _ship.to_global(Vector3(-75.0, 2.6, 8.0))
	_player.reset_physics_interpolation()
	await wait_physics_frames(int((NpcTour.AWAY_TIME - 2.0) * Engine.physics_ticks_per_second))
	assert_not_null(_brannik.routine.tour, "waits a while")
	await wait_physics_frames(int(4.0 * Engine.physics_ticks_per_second))
	assert_null(_brannik.routine.tour, "then gives up")


func test_he_rides_the_lift_to_the_lower_deck() -> void:
	await _load()
	await _start_tour()
	var lift := _ship.get_node(NpcWalker.LIFT) as Lift
	var tour: NpcTour = _brannik.routine.tour
	var lobby := _ship.get_node("Tour/Lift") as Node3D
	_brannik.global_transform = lobby.global_transform
	tour.stop = tour.tour.stops.find(_stop(tour.tour, &"MedicalBay"))
	_player.global_position = lobby.global_position + Vector3(0.0, 0.1, 2.0)
	_player.reset_physics_interpolation()
	await _until(
		func() -> bool: return _brannik.routine._walker.ride == NpcWalker.Ride.WAITING, 15.0
	)
	# He calls it on his next step at the gate.
	await wait_physics_frames(2)
	assert_eq(lift.deck, Lift.Deck.UPPER, "called up to his deck")
	await _until(
		func() -> bool: return _brannik.routine._walker.ride == NpcWalker.Ride.BOARDING, 10.0
	)
	assert_true(lift.boarding, "holds it while he steps on")
	# A player on the platform doesn't send it off without him.
	_player.global_position = lift.platform_floor() + lift.global_basis.x * 1.5 + Vector3.UP * 0.1
	_player.reset_physics_interpolation()
	await wait_physics_frames(int(lift.departure_delay * 2.0 * Engine.physics_ticks_per_second))
	assert_false(lift.moving and _brannik.routine._walker.ride == NpcWalker.Ride.BOARDING)
	await _until(
		func() -> bool: return _brannik.routine._walker.ride == NpcWalker.Ride.RIDING, 10.0
	)
	await _until(func() -> bool: return _brannik.routine._walker.ride == NpcWalker.Ride.NONE, 15.0)
	assert_almost_eq(_ship.to_local(_brannik.global_position).y, 2.5, 0.01, "on the lower deck")
	await _until(func() -> bool: return not _brannik.routine.is_underway(), 30.0)
	var medical := _ship.get_node("Tour/MedicalBay") as Node3D
	assert_almost_eq(_brannik.global_position, medical.global_position, Vector3.ONE * 0.05)


## The test map, its story with `flags` set before anything runs.
func _load(flags: Array[StringName] = []) -> void:
	_map = TEST_MAP.instantiate() as Node3D
	_ship = _map.get_node("Ship") as Ship
	for flag: StringName in flags:
		_ship.story.set_flag(flag)
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_brannik = _ship.get_node(QUARTERMASTER) as Npc
	await wait_physics_frames(2)


## Hears the offer and "Show me the ship" to the end: the tour starts.
func _start_tour() -> void:
	_brannik.open(_player)
	while _brannik.talk.topic:
		_brannik.talk.press()
	_brannik.talk.talk_about(_brannik.profile.tour.invite)
	while _brannik.talk.topic:
		_brannik.talk.press()
	await wait_process_frames(2)


func _stop(tour: Tour, id: StringName) -> TourStop:
	for stop: TourStop in tour.stops:
		if stop.id == id:
			return stop
	return null


## Waits physics frames until `done` holds, `seconds` at most.
func _until(done: Callable, seconds: float) -> void:
	for i: int in int(seconds * Engine.physics_ticks_per_second):
		if done.call():
			return
		await wait_physics_frames(1)
