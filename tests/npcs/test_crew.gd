extends GutTest
## The eight crew members aboard (`Npc`): each at their post, telling them apart, the pilot in the
## cockpit while a destination is chosen and the ship flies (walking there and back).

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
## Each crew member's spot in the ship, and their name plate (in English, then in German).
const CREW: Dictionary[String, String] = {
	"Rooms/Lower/Armory/Quartermaster": "Brannik · Quartermaster",
	"Rooms/Upper/Bridge/Pilot": "Tamsin · Pilot",
	"Rooms/Lower/EngineRoom/Engineer": "Okoro · Engineer",
	"Rooms/Lower/MedicalBay/Medic": "Ilse · Medic",
	"Rooms/Lower/Weapons/Gunsmith": "Dace · Gunsmith",
	"Rooms/Lower/Armor/SuitTech": "Wren · Suit tech",
	"Rooms/Lower/Miners/MinerMechanic": "Hollis · Miner mechanic",
	"Rooms/Upper/MessHall/Cook": "Fenna · Cook",
}
const PLATES_DE: Dictionary[String, String] = {
	"Rooms/Lower/Armory/Quartermaster": "Brannik · Quartiermeister",
	"Rooms/Upper/Bridge/Pilot": "Tamsin · Pilotin",
	"Rooms/Lower/EngineRoom/Engineer": "Okoro · Ingenieur",
	"Rooms/Lower/MedicalBay/Medic": "Ilse · Ärztin",
	"Rooms/Lower/Weapons/Gunsmith": "Dace · Waffenschmied",
	"Rooms/Lower/Armor/SuitTech": "Wren · Anzugtechnikerin",
	"Rooms/Lower/Miners/MinerMechanic": "Hollis · Minermechaniker",
	"Rooms/Upper/MessHall/Cook": "Fenna · Köchin",
}

var _map: Node3D
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func after_each() -> void:
	TranslationServer.set_locale("en")


func test_everyone_at_their_post() -> void:
	var cabins: Array[int] = []
	for path: String in CREW:
		var npc := _ship.get_node(path) as Npc
		assert_eq(npc.get_plate_text(), CREW[path])
		assert_true(npc.has_news(), path + ": the greeting is new")
		assert_does_not_have(cabins, npc.profile.cabin, path + ": a cabin of their own")
		cabins.append(npc.profile.cabin)
	TranslationServer.set_locale("de")
	for path: String in CREW:
		assert_eq((_ship.get_node(path) as Npc).get_plate_text(), PLATES_DE[path])


func test_their_topics_are_their_own_and_open_after_talking() -> void:
	for path: String in CREW:
		var profile: NpcProfile = (_ship.get_node(path) as Npc).profile
		var greeting: Topic = profile.dialogue.greeting
		assert_eq(greeting.id, StringName("%s.greeting" % profile.id))
		assert_gt(profile.dialogue.topics.size(), 1, path)
		for topic: Topic in profile.dialogue.topics:
			assert_true(Story.is_valid_flag(topic.id), String(topic.id))
			assert_string_starts_with(String(topic.id), String(profile.id) + ".")
			assert_false(
				topic.requires.is_empty(), String(topic.id) + " after the greeting or more"
			)
			assert_false(topic.lines.is_empty(), String(topic.id))


func test_each_has_a_model_of_their_own() -> void:
	var models: Array[String] = []
	for path: String in CREW:
		var npc := _ship.get_node(path) as Npc
		var model := npc.body.get_node("Model") as Node3D
		assert_string_starts_with(model.scene_file_path, "res://assets/npcs/", path)
		assert_does_not_have(models, model.scene_file_path, path)
		models.append(model.scene_file_path)
		assert_not_null(model.find_child("HeadTop", true, false), path + ": their head's top")


func test_pilot_walks_to_the_cockpit_sits_and_walks_back() -> void:
	var pilot := _ship.get_node("Rooms/Upper/Bridge/Pilot") as Npc
	var home: Vector3 = pilot.global_position
	var seat: Vector3 = pilot.flight_seat.global_position
	var console := _ship.get_node("Rooms/Upper/Cockpit/FlightConsole") as Node3D
	assert_lt(seat.distance_to(console.global_position), 2.0, "the seat at the flight console")
	assert_true(_ship.flight.take_off())
	await _until(func() -> bool: return pilot.body.is_walking(), 10.0)
	await wait_physics_frames(30)
	assert_true(pilot.body.is_walking(), "she walks, she doesn't appear there")
	assert_true(pilot.is_underway())
	assert_gt(pilot.global_position.distance_to(home), 0.5, "on her way")
	await _until(func() -> bool: return pilot.body.sitting, 40.0)
	assert_true(pilot.body.sitting, "sits down in the pilot seat")
	assert_almost_eq(pilot.global_position, seat, Vector3.ONE * 0.05)
	assert_false(_ship.flight.is_flying(), "the take-off is over before she's there")
	await wait_physics_frames(int((Npc.SEAT_LINGER - 1.0) * Engine.physics_ticks_per_second))
	assert_true(pilot.body.sitting, "she still sits a while after the flight")
	await _until(func() -> bool: return pilot.body.is_walking(), 5.0)
	assert_false(pilot.body.sitting, "then gets up")
	await _until(func() -> bool: return not pilot.is_underway(), 60.0)
	assert_almost_eq(pilot.global_position, home, Vector3.ONE * 0.05, "back on the bridge")


func test_a_chosen_destination_sends_her_to_the_seat_to_wait_for_the_course() -> void:
	var pilot := _ship.get_node("Rooms/Upper/Bridge/Pilot") as Npc
	var voyage: Voyage = _ship.voyage
	assert_true(voyage.choose(voyage.offers[1]), "Set as destination")
	await _until(func() -> bool: return pilot.body.is_walking(), 10.0)
	assert_true(pilot.body.is_walking(), "she's on her way before the course is set")
	await _until(func() -> bool: return pilot.body.sitting, 40.0)
	assert_true(pilot.body.sitting)
	assert_false(_ship.flight.is_flying())
	await wait_physics_frames(int(Npc.SEAT_LINGER * 2.0 * Engine.physics_ticks_per_second))
	assert_true(pilot.body.sitting, "waits there for the course")
	voyage.destination = null
	await _until(func() -> bool: return pilot.body.is_walking(), Npc.SEAT_LINGER + 3.0)
	assert_false(pilot.body.sitting, "no destination any more: back to the bridge")


func test_walking_back_she_stops_for_a_player() -> void:
	var pilot := _ship.get_node("Rooms/Upper/Bridge/Pilot") as Npc
	var player := _map.get_node("Player") as Player
	_ship.flight.take_off()
	await _until(func() -> bool: return pilot.body.sitting, 40.0)
	await _until(func() -> bool: return pilot.body.is_walking(), 15.0)
	await wait_physics_frames(60)
	player.global_position = pilot.global_position + pilot.global_basis.z * 1.5
	player.reset_physics_interpolation()
	await wait_physics_frames(10)
	var stopped: Vector3 = pilot.global_position
	await wait_physics_frames(60)
	assert_false(pilot.body.is_walking(), "stands while a player is close")
	assert_almost_eq(pilot.global_position, stopped, Vector3.ONE * 0.01)
	player.global_position = pilot.global_position + Vector3(0.0, 0.0, 8.0)
	player.reset_physics_interpolation()
	await wait_physics_frames(30)
	assert_true(pilot.body.is_walking(), "walks on once they're gone")


## Waits physics frames until `done` holds, `seconds` at most.
func _until(done: Callable, seconds: float) -> void:
	for i: int in int(seconds * Engine.physics_ticks_per_second):
		if done.call():
			return
		await wait_physics_frames(1)
