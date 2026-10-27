extends GutTest
## NPCs know where they are (`NpcRoutine.get_room`, the map's `RoomPlan`): the room they stand in,
## their own, and what they say outside it (`Topic.away_lines`).

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
## Every named NPC's profile folder (the colonists only remark).
const PROFILES: Array[String] = ["res://game/npcs/crew/", "res://game/npcs/ostra/"]
## What in a line needs the NPC's own room around them (whole words, lowercase): a topic with such
## a line has lines for elsewhere. Ostra's greetings are heard before their NPC ever leaves their
## room.
const PLACE_WORDS: Array[String] = [
	"(?<!room )next door",
	"(shelves|counter|rack|wall) behind me",
	"this (table|room|shield|bench)",
	"(right|up|down) here",
	"here (at|in) the",
	"(stored|beds|armor) here",
	"wake up here",
	"walk in here",
	"welcome to the",
	"come in",
	"look at this",
	"there in its",
]

var _map: Node3D
var _player: Player
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	(_map.get_node("Ship") as Ship).story.set_flag(&"quartermaster.tour_offer")
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func test_the_ship_knows_its_rooms() -> void:
	var plan: RoomPlan = _ship.room_plan
	for path: String in [
		"Rooms/Lower/Armory", "Rooms/Upper/Bridge", "Rooms/Upper/Cockpit", "Rooms/CargoBay"
	]:
		var room := _ship.get_node(path) as Node3D
		assert_eq(plan.room_at(room.global_position + Vector3.UP * 0.1), room.name, path)
	# The armory's door to the corridor, in the wall between them (the armory ends at z -3, the
	# corridor starts at -2.5): it keeps the room someone comes from.
	var armory: Vector3 = _ship.to_local(
		(_ship.get_node("Rooms/Lower/Armory") as Node3D).global_position
	)
	var doorway: Vector3 = _ship.to_global(Vector3(armory.x, armory.y, -2.75))
	assert_eq(plan.room_at(doorway, &"Armory"), &"Armory", "from the armory")
	assert_eq(plan.room_at(doorway, &"LowerCorridor"), &"LowerCorridor", "from the corridor")
	assert_eq(plan.room_at(doorway), &"", "in the wall, from nowhere")
	assert_eq(plan.room_at(_ship.to_global(Vector3(armory.x, armory.y, 0.0))), &"LowerCorridor")
	assert_eq(plan.room_at(Vector3(1000.0, 0.0, 0.0), &"Armory"), &"Armory", "outside: kept")


func test_everyone_knows_their_own_room() -> void:
	for npc: Npc in _crew():
		var room: StringName = npc.get_parent().name
		assert_eq(npc.routine.get_own_room(), room, npc.name)
		assert_eq(npc.routine.get_room(), room, npc.name)
		assert_false(npc.routine.is_away(), npc.name)


func test_away_from_their_room_they_say_it_without_the_room() -> void:
	var npc := _ship.get_node("Rooms/Lower/Weapons/Gunsmith") as Npc
	var greeting: Topic = npc.profile.dialogue.greeting
	assert_false(greeting.away_lines.is_empty())
	var corridor := _ship.get_node("Rooms/Lower/LowerCorridor") as Node3D
	npc.global_position = corridor.global_position
	_player.global_position = corridor.global_position + Vector3(1.5, 0.0, 0.0)
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	assert_eq(npc.routine.get_room(), &"LowerCorridor")
	assert_true(npc.routine.is_away())
	npc.open(_player)
	await wait_process_frames(1)
	assert_eq(npc.topic, greeting)
	assert_eq(npc.get_topic_lines(), greeting.away_lines)
	assert_eq((npc.bubble.content as SpeechBubble).get_line(), greeting.away_lines[0])
	npc.close()


func test_the_pilot_in_the_cockpit_is_away_from_the_bridge() -> void:
	var pilot := _ship.get_node("Rooms/Upper/Bridge/Pilot") as Npc
	pilot.global_position = pilot.flight_seat.global_position
	assert_eq(pilot.routine.get_room(), &"Cockpit")
	assert_true(pilot.routine.is_away())
	var greeting: Topic = pilot.profile.dialogue.greeting
	assert_eq(greeting.lines_for(false, true), greeting.away_lines, "not 'here at the navigator'")
	assert_eq(greeting.lines_for(false, false), greeting.lines)
	assert_eq(greeting.lines_for(true, true), greeting.away_lines, "a guest too")


func test_lines_that_need_their_room_have_lines_for_elsewhere() -> void:
	for profile: NpcProfile in _profiles():
		var dialogue: Dialogue = profile.dialogue
		for prompt: String in dialogue.get_prompts():
			assert_eq(_place_word(prompt), "", "%s prompt: %s" % [profile.id, prompt])
		var topics: Array[Topic] = dialogue.topics.duplicate()
		var stays_until_greeted: bool = profile.resource_path.begins_with(PROFILES[1])
		if not stays_until_greeted:
			topics.append(dialogue.greeting)
		for topic: Topic in topics:
			if not topic.away_lines.is_empty():
				assert_eq(topic.away_lines.size(), topic.lines.size(), String(topic.id))
				continue
			for line: String in topic.lines:
				assert_eq(_place_word(line), "", "%s needs away_lines: %s" % [topic.id, line])


func _place_word(line: String) -> String:
	var lower: String = line.to_lower()
	for words: String in PLACE_WORDS:
		var pattern := RegEx.create_from_string("\\b(%s)\\b" % words)
		var found: RegExMatch = pattern.search(lower)
		if found:
			return found.get_string()
	return ""


func _crew() -> Array[Npc]:
	var crew: Array[Npc] = []
	for node: Node in _ship.find_children("*", "Npc", true, false):
		crew.append(node as Npc)
	assert_eq(crew.size(), 8)
	return crew


func _profiles() -> Array[NpcProfile]:
	var profiles: Array[NpcProfile] = []
	for folder: String in PROFILES:
		for file: String in ResourceLoader.list_directory(folder):
			if file.ends_with(".tres"):
				var profile := load(folder + file) as NpcProfile
				if profile and profile.dialogue:
					profiles.append(profile)
	assert_gt(profiles.size(), 10)
	return profiles
