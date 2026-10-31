extends GutTest
## The crew who join later at their places at Waypost Ostra (`Npc.waits_to_join`), walking aboard
## once they join (`NpcBoarding`): the ship waits for them, its ramp stays down, their crew member
## aboard takes over at the door; their places stay empty afterwards.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
## Their places at Ostra and their posts aboard, by name.
const PLACES: Dictionary[String, String] = {
	"Dace": "Rooms/Lower/Weapons/Gunsmith",
	"Wren": "Rooms/Lower/Armor/SuitTech",
	"Fenna": "Rooms/Upper/MessHall/Cook",
}

var _map: Node3D
var _player: Player
var _voyage: Voyage
var _ship: Ship
var _station: SpaceStation


func after_each() -> void:
	await wait_process_frames(1)


func test_they_wait_at_their_places_until_they_join() -> void:
	await _dock_at_ostra(false)
	for who: String in PLACES:
		var waiting := _people(who)
		var aboard := _ship.get_node(PLACES[who]) as Npc
		assert_eq(waiting.profile, aboard.profile, who)
		assert_true(waiting.is_present() and waiting.visible, who + " at their place")
		assert_false(waiting.use_point.enabled, who + ": their topics come with their quests")
		assert_false(waiting.has_news(_player), who + ": no marker")
		assert_false(aboard.is_present(), who + " not aboard")
	assert_true(_people("Fenna").body.sitting, "Fenna sits at Rook's booth")
	assert_false((_station.get_node("DaceStall/Shutter") as Node3D).visible, "his stall is open")


func test_joining_walks_them_aboard() -> void:
	await _dock_at_ostra(false)
	_ship.ramp_open = true
	await _until(func() -> bool: return _ship.is_ramp_down(), 5.0)
	_station.navigation.bake()
	await _until(func() -> bool: return _station.navigation.is_baked(), 10.0)
	await wait_physics_frames(2)
	var dace := _people("Dace")
	var gunsmith := _ship.get_node(PLACES["Dace"]) as Npc
	var foot: Vector3 = _ship.ramp_way()[0]
	# Close to the ramp's foot already, so the walk is short.
	dace.global_position = foot + _ship.global_basis.x * 3.0
	dace.reset_physics_interpolation()
	_ship.story.set_flag(dace.profile.join_flag)
	assert_true(dace.is_present(), "on his way")
	assert_eq(NpcBoarding.walking(get_tree()), [dace] as Array[Npc])
	assert_false(gunsmith.is_present(), "not aboard yet")
	await wait_physics_frames(2)
	assert_false(_ship.ramp_button.enabled, "the ramp stays down for him")
	var console := _ship.get_node("Rooms/Upper/Cockpit/FlightConsole") as FlightStation
	assert_false(console.can_launch(), "the ship waits for him")
	await _until(func() -> bool: return dace.global_position.y > foot.y + 1.0, 10.0)
	assert_gt(dace.global_position.y, foot.y + 1.0, "up the ramp")
	await _until(func() -> bool: return gunsmith.is_present(), 10.0)
	assert_true(gunsmith.is_present() and gunsmith.visible, "aboard")
	assert_false(dace.is_present() or dace.visible, "gone from the ramp")
	assert_true(NpcBoarding.walking(get_tree()).is_empty())
	var door: Vector3 = _ship.ramp_way()[1]
	assert_lt(gunsmith.global_position.distance_to(door), 1.5, "comes in at the door")
	await wait_physics_frames(2)
	assert_true(_ship.ramp_button.enabled)
	await _until(func() -> bool: return gunsmith.body.is_walking(), 5.0)
	assert_true(gunsmith.body.is_walking(), "on to his post")


func test_their_places_stay_empty_once_aboard() -> void:
	await _dock_at_ostra(true)
	for who: String in PLACES:
		var waiting := _people(who)
		assert_false(waiting.is_present() or waiting.visible, who)
		assert_true((_ship.get_node(PLACES[who]) as Npc).is_present(), who)
	assert_true(NpcBoarding.walking(get_tree()).is_empty(), "nobody walks aboard on a load")
	assert_true((_station.get_node("DaceStall/Shutter") as Node3D).visible, "his shutter is down")


## The test map docked at Ostra, with the crew who join later aboard already or not.
func _dock_at_ostra(crew_joined: bool) -> void:
	SaveGame.directory = ""
	_map = TEST_MAP.instantiate(crew_joined) as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_voyage = _map.get_node("Voyage") as Voyage
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)
	var ostra: CelestialBody = _voyage.settings.system.body_by_id(&"ostra")
	_voyage.select(_voyage.offer_for_station(ostra))
	_voyage.skip_flight()
	await wait_physics_frames(3)
	_station = _voyage.location as SpaceStation


func _people(who: String) -> Npc:
	return _station.get_node("People/" + who) as Npc


func _until(done: Callable, seconds: float) -> void:
	for i: int in int(seconds * Engine.physics_ticks_per_second):
		if done.call():
			return
		await wait_physics_frames(1)
