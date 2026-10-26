extends GutTest
## The eight crew members aboard (`Npc`): each at their post, telling them apart, the pilot in the
## cockpit while the ship flies.

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


func test_pilot_flies_from_the_cockpit() -> void:
	var pilot := _ship.get_node("Rooms/Upper/Bridge/Pilot") as Npc
	var on_bridge: Vector3 = pilot.global_position
	var in_cockpit: Vector3 = pilot.flight_spot.global_position
	var cockpit := _ship.get_node("Rooms/Upper/Cockpit") as Node3D
	var console := cockpit.get_node("FlightConsole") as Node3D
	assert_lt(in_cockpit.distance_to(console.global_position), 3.0, "beside the flight console")
	assert_true(_ship.flight.take_off())
	await wait_process_frames(2)
	assert_true(_ship.flight.is_flying())
	assert_almost_eq(pilot.global_position, in_cockpit, Vector3.ONE * 0.01, "in the cockpit")
	_ship.flight.skip()
	await wait_process_frames(2)
	assert_false(_ship.flight.is_flying())
	assert_almost_eq(pilot.global_position, on_bridge, Vector3.ONE * 0.01, "back on the bridge")
