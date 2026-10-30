extends GutTest
## Overheard talks (`OverheardTalk`, `OverheardTalks`, `TalkSpot`): a talk waits for its flags,
## then both speakers walk to its spot's places and wait there; a player coming close starts it,
## the lines go one after another in the speakers' bubbles while neither can be talked to (both
## facing each other, no plates), it plays to the end with nobody close, and its flag is set at the
## end; every talk in the catalog keeps to the scheme.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const COOK: String = "Rooms/Upper/MessHall/Cook"
const PILOT: String = "Rooms/Upper/Bridge/Pilot"
const SPOT: String = "Rooms/Upper/MessHall/MessTable"
const TALK_SPOT_SCRIPT: String = "res://game/talks/talk_spot.gd"

var _map: Node3D
var _ship: Ship
var _player: Player
var _cook: Npc
var _pilot: Npc
var _spot: TalkSpot
var _talk: OverheardTalk


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	_ship = _map.get_node("Ship") as Ship
	_ship.talks.catalog = TalkCatalog.new()
	_talk = _make_talk()
	_ship.talks.catalog.talks = [_talk]
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_cook = _ship.get_node(COOK) as Npc
	_pilot = _ship.get_node(PILOT) as Npc
	_spot = _ship.get_node(SPOT) as TalkSpot
	await wait_physics_frames(2)


func test_a_talk_waits_for_its_flags() -> void:
	await wait_physics_frames(int(OverheardTalks.PICK_TIME * Engine.physics_ticks_per_second) + 2)
	assert_null(_ship.talks.talk, "its beat isn't out yet")
	assert_null(_cook.routine.talk_place)
	_ship.story.set_flag(&"beat.test_talk")
	await _wait_for_pick()
	assert_eq(_ship.talks.talk, _talk, "waits once its flags are set")
	assert_eq(_cook.routine.talk_place, _spot.get_place(0), "the first to speak takes the first")
	assert_eq(_pilot.routine.talk_place, _spot.get_place(1))
	assert_eq(_cook.routine.get_post(), _spot.get_place(0).global_transform, "walks there")


func test_the_places_face_each_other_turned_to_the_front() -> void:
	var first: Vector3 = _spot.get_place(0).global_basis.z
	var second: Vector3 = _spot.get_place(1).global_basis.z
	var across: Vector3 = _spot.get_place(1).global_position - _spot.get_place(0).global_position
	assert_almost_eq(across.length(), TalkSpot.GAP, 0.001)
	assert_gt(first.dot(across), 0.8, "the first looks at the second")
	assert_lt(second.dot(across), -0.8, "the second at the first")
	assert_gt(first.dot(_spot.global_basis.z), 0.2, "both turned to the front")
	assert_gt(second.dot(_spot.global_basis.z), 0.2)


func test_a_player_close_starts_it_and_it_plays_to_the_end() -> void:
	_player.global_position = _spot.global_position + Vector3(0.0, 0.1, 20.0)
	_player.reset_physics_interpolation()
	_ship.story.set_flag(&"beat.test_talk")
	await _wait_for_pick()
	_stand_at_places()
	await wait_physics_frames(30)
	assert_false(_ship.talks.is_playing(), "waits for someone to come close")
	assert_true(_cook.can_use(_player), "can be talked to while it waits")
	_player.global_position = _spot.global_position + Vector3(0.0, 0.1, 3.0)
	_player.reset_physics_interpolation()
	await wait_physics_frames(3)
	assert_true(_ship.talks.is_playing(), "starts with a player close")
	assert_true(_cook.bubble.visible, "the first line above the cook")
	assert_eq((_cook.bubble.content as SpeechBubble).get_line(), _talk.lines[0].text)
	assert_false(_pilot.bubble.visible)
	assert_false(_cook.can_use(_player), "can't be talked to while it plays")
	assert_false(_pilot.use_point.enabled)
	assert_false(_pilot.body.plate_allowed, "no plate under the other's bubble")
	assert_true(_cook.body.holds_facing, "they face each other, not the player")
	# The player walks off: it plays on.
	_player.global_position = _spot.global_position + Vector3(0.0, 0.1, 25.0)
	_player.reset_physics_interpolation()
	await _until(func() -> bool: return _pilot.bubble.visible, 10.0)
	assert_eq((_pilot.bubble.content as SpeechBubble).get_line(), _talk.lines[1].text)
	assert_false(_cook.bubble.visible, "one bubble at a time")
	await _until(func() -> bool: return not _ship.talks.is_playing(), 10.0)
	assert_true(_ship.story.is_set(_talk.flag()), "played to the end without anyone close")
	assert_false(_pilot.bubble.visible)
	assert_null(_cook.routine.talk_place, "back to what they did")
	assert_true(_cook.can_use(_player))
	assert_true(_pilot.use_point.enabled)
	await _wait_for_pick()
	assert_null(_ship.talks.talk, "once")


func test_it_doesnt_start_while_someone_talks_to_one_of_them() -> void:
	_ship.story.set_flag(&"beat.test_talk")
	await _wait_for_pick()
	_stand_at_places()
	_player.global_position = _cook.global_position + Vector3(0.0, 0.1, 1.0)
	_player.reset_physics_interpolation()
	_cook.open(_player)
	await wait_physics_frames(10)
	assert_false(_ship.talks.is_playing())
	_cook.close()
	await wait_physics_frames(3)
	assert_true(_ship.talks.is_playing(), "starts once the talk with the player is over")


func test_a_held_talk_leaves_no_flag() -> void:
	var held: OverheardTalk = _make_talk()
	held.id = &"held"
	held.requires = []
	_ship.talks.hold(held)
	await _wait_for_pick()
	assert_eq(_ship.talks.talk, held, "before the catalog's")
	_stand_at_places()
	_player.global_position = _spot.global_position + Vector3(0.0, 0.1, 3.0)
	_player.reset_physics_interpolation()
	await _until(func() -> bool: return _ship.talks.is_playing(), 2.0)
	await _until(func() -> bool: return not _ship.talks.is_playing(), 20.0)
	assert_false(_ship.story.is_set(held.flag()))


func test_every_talk_keeps_to_the_scheme() -> void:
	var spots: Array[String] = _talk_spots("res://game")
	for spot: String in spots:
		assert_eq(spots.count(spot), 1, "talk spot %s: its name unique" % spot)
	for talk: OverheardTalk in OverheardTalks.CATALOG.talks:
		assert_true(Story.is_valid_flag(talk.flag()), "%s: its flag" % talk.id)
		assert_eq(talk.speakers().size(), 2, "%s: two talking" % talk.id)
		for speaker: StringName in talk.speakers():
			assert_not_null(NpcProfile.find(speaker), "%s: %s" % [talk.id, speaker])
		assert_has(spots, String(talk.spot), "%s: its spot" % talk.id)
		assert_false(talk.requires.is_empty(), "%s: opened by the story" % talk.id)
		for line: TalkLine in talk.lines:
			assert_false(line.text.is_empty(), "%s: what's said" % talk.id)


## A talk between the cook and the pilot at the mess table, opened by `beat.test_talk`.
func _make_talk() -> OverheardTalk:
	var talk := OverheardTalk.new()
	talk.id = &"test"
	talk.spot = &"MessTable"
	talk.requires = [&"beat.test_talk"] as Array[StringName]
	for speaker: StringName in [&"cook", &"pilot"]:
		var line := TalkLine.new()
		line.npc = speaker
		line.text = "Short line."
		talk.lines.append(line)
	talk.lines[1].text = "Another one."
	return talk


## Puts both speakers at their places, facing their way (walking there is the routine's).
func _stand_at_places() -> void:
	for npc: Npc in [_cook, _pilot]:
		npc.global_transform = npc.routine.talk_place.global_transform
		npc.reset_physics_interpolation()


func _wait_for_pick() -> void:
	await wait_physics_frames(int(OverheardTalks.PICK_TIME * Engine.physics_ticks_per_second) + 2)


func _until(done: Callable, seconds: float) -> void:
	for i: int in int(seconds * Engine.physics_ticks_per_second):
		if done.call():
			return
		await wait_physics_frames(1)


## The names of the talk spots in the scenes under `dir` (and its folders).
func _talk_spots(dir: String) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() != "tscn":
			continue
		var text: String = FileAccess.get_file_as_string(dir.path_join(file))
		if TALK_SPOT_SCRIPT not in text:
			continue
		var state: SceneState = (load(dir.path_join(file)) as PackedScene).get_state()
		for node: int in state.get_node_count():
			for property: int in state.get_node_property_count(node):
				var value: Variant = state.get_node_property_value(node, property)
				if value is Script and (value as Script).resource_path == TALK_SPOT_SCRIPT:
					found.append(String(state.get_node_name(node)))
	for folder: String in DirAccess.get_directories_at(dir):
		found.append_array(_talk_spots(dir.path_join(folder)))
	return found
