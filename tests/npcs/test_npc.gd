extends GutTest
## Crew members aboard (`Npc`): the quartermaster in the armory, talking to them, their topics.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")

var _map: Node3D
var _player: Player
var _ship: Ship
var _npc: Npc


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	_npc = _ship.get_node("Rooms/Lower/Armory/Quartermaster") as Npc
	await wait_physics_frames(2)


func after_each() -> void:
	TranslationServer.set_locale("en")


func test_quartermaster_stands_in_the_armory() -> void:
	assert_not_null(_npc.profile)
	assert_eq(_npc.get_story(), _ship.story)
	assert_eq(_npc.ship, _ship)
	assert_eq(_npc.get_plate_text(), "Brannik · Quartermaster")
	TranslationServer.set_locale("de")
	assert_eq(_npc.get_plate_text(), "Brannik · Quartiermeister")


func test_name_plate_and_marker_show_near() -> void:
	_player.global_position = _npc.global_position + Vector3(0.0, 0.0, 10.0)
	_player.reset_physics_interpolation()
	await wait_process_frames(2)
	assert_false(_npc._plate.visible, "far away")
	assert_true(_npc._new_marker.visible, "the greeting is new")
	_player.global_position = _npc.global_position + Vector3(0.0, 0.0, 2.0)
	_player.reset_physics_interpolation()
	await wait_process_frames(2)
	assert_true(_npc._plate.visible, "near")


func test_first_talk_plays_the_greeting() -> void:
	await _talk()
	var greeting: Topic = _npc.profile.dialogue.greeting
	assert_eq(_npc.user, _player)
	assert_eq(_npc.topic, greeting)
	assert_true(_npc.bubble.visible)
	var speech := _npc.bubble.content as SpeechBubble
	assert_eq(speech.get_line(), greeting.lines[0])
	for i: int in greeting.lines.size():
		_npc.press()
	assert_null(_npc.topic, "back to the list")
	assert_true(_ship.story.is_set(greeting.id), "heard")
	assert_eq(speech.get_line(), _npc.profile.dialogue.prompt)
	assert_eq(
		_titles(),
		["Ammo", "Spare magazines", "Reloading", "Shooting range"],
		"timing needs reloading, Brask owning one"
	)


func test_greeting_plays_only_once() -> void:
	_ship.story.set_flag(_npc.profile.dialogue.greeting.id)
	await _talk()
	assert_null(_npc.topic, "straight to the list")


func test_topics_open_up_and_lose_their_dot() -> void:
	_ship.story.set_flag(_npc.profile.dialogue.greeting.id)
	await _talk()
	var card := _npc.card_menu as TalkCard
	assert_string_starts_with(card.get_button("Reloading").text, TalkCard.NEW_DOT)
	card.get_button("Reloading").pressed.emit()
	assert_eq(_npc.topic.id, &"quartermaster.reload")
	assert_not_null(card.get_button("Continue"))
	while _npc.topic:
		_npc.press()
	assert_eq(
		_titles(), ["Ammo", "Spare magazines", "Reloading", "Timing reload", "Shooting range"]
	)
	assert_false(card.get_button("Reloading").text.begins_with(TalkCard.NEW_DOT), "heard")
	assert_true(_npc.has_news(), "the others are new")
	for topic: Topic in _npc.get_choices():
		_ship.story.set_flag(topic.id)
	assert_false(_npc.has_news())


func test_brask_topic_once_it_is_unlocked() -> void:
	_ship.story.set_flag(_npc.profile.dialogue.greeting.id)
	# Hearing some opens up others.
	while _npc.has_news(_player):
		for topic: Topic in _npc.get_choices(_player):
			_ship.story.set_flag(topic.id)
	assert_false(_titles(_player).has("Brask"), "locked")
	_player.arsenal.unlock(BRASK)
	assert_true(_titles(_player).has("Brask"))
	assert_true(_npc.has_news(_player), "Brask is new")
	await wait_process_frames(1)
	assert_true(_npc._new_marker.visible)


func test_gamepad_picks_steps_back_and_closes() -> void:
	_ship.story.set_flag(_npc.profile.dialogue.greeting.id)
	await _talk()
	assert_eq(_npc.choice, 0)
	_npc.step(Vector2.DOWN)
	assert_eq(_npc.choice, 1)
	_npc.step(Vector2.UP)
	_npc.step(Vector2.UP)
	assert_eq(_npc.choice, _npc.get_choices().size(), "wraps to Goodbye")
	_npc.step(Vector2.DOWN)
	_npc.press()
	assert_eq(_npc.topic.id, &"quartermaster.ammo")
	_press(&"pause")
	assert_null(_npc.topic, "a step back to the list")
	assert_eq(_npc.user, _player, "still talking")
	assert_false(_ship.story.is_set(&"quartermaster.ammo"), "not heard to the end")
	_press(&"pause")
	assert_null(_npc.user, "closed")
	assert_false(_npc.bubble.visible)


func test_goodbye_closes() -> void:
	_ship.story.set_flag(_npc.profile.dialogue.greeting.id)
	await _talk()
	(_npc.card_menu as TalkCard).get_button("Goodbye").pressed.emit()
	assert_null(_npc.user)
	assert_null(_player.menu)


func test_they_face_each_other() -> void:
	await _talk()
	await wait_physics_frames(30)
	var to_npc: Vector3 = _npc.global_position - _player.global_position
	to_npc.y = 0.0
	var player_facing: Vector3 = -_player.global_basis.z
	assert_gt(player_facing.dot(to_npc.normalized()), 0.9, "the player faces them")
	var npc_facing: Vector3 = _npc._body.global_basis.z
	assert_gt(npc_facing.dot(-to_npc.normalized()), 0.9, "they face the player")


func _talk() -> void:
	_player.global_position = _npc.use_point.global_position + Vector3(0.0, 0.0, 1.0)
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	assert_eq(Interactable.nearest(get_tree(), _player.global_position), _npc.use_point)
	_npc.use_point.use(_player)
	await wait_process_frames(1)


func _titles(listener: Player = null) -> Array[String]:
	var titles: Array[String] = []
	for topic: Topic in _npc.get_choices(listener):
		titles.append(topic.title)
	return titles


## Presses and releases `action` as an input event.
func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input(event)
