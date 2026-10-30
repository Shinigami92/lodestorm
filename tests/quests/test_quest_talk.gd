extends GutTest
## Quests at an NPC (`Npc`, `NpcTalk`, `TalkCard`): the diamond marker, the offer card, accepting,
## and handing in a step with the rest paid from the hold.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const QUEST_LOG_TEST := preload("res://tests/quests/test_quest_log.gd")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const MERISK: AlloyType = preload("res://game/refinery/alloys/alloy_merisk.tres")

var _map: Node3D
var _player: Player
var _ship: Ship
var _npc: Npc
var _quest: Quest


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	var ship := _map.get_node("Ship") as Ship
	# Past his tour's offer and his greeting: the list shows at once.
	ship.story.set_flag(&"quartermaster.tour_offer")
	ship.story.set_flag(&"quartermaster.greeting")
	_quest = QUEST_LOG_TEST.make_quest(&"ammo_run", &"quartermaster")
	ship.quests.catalog = QuestCatalog.new()
	ship.quests.catalog.quests = [_quest]
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = ship
	_npc = _ship.get_node("Rooms/Lower/Armory/Quartermaster") as Npc
	await wait_physics_frames(2)


func test_a_quest_offered_shows_a_diamond() -> void:
	_player.global_position = _npc.global_position + Vector3(0.0, 0.0, 3.0)
	_player.reset_physics_interpolation()
	await wait_process_frames(2)
	assert_true(_npc.has_quest_news(_player))
	assert_true(_npc._quest_marker.visible, "a diamond")
	assert_false(_npc._news_marker.visible)
	_ship.quests.accept(_quest, [_player])
	await wait_process_frames(1)
	assert_false(_npc.has_quest_news(_player), "nothing to hand in yet")
	assert_false(_npc._quest_marker.visible)


func test_offer_card_accepts() -> void:
	await _talk()
	assert_eq(_npc.get_choices()[0], _quest.offer, "quests first")
	_npc.talk.press()
	assert_eq(_npc.talk.topic, _quest.offer, "told like a topic")
	for line: String in _quest.offer.lines:
		_npc.talk.press()
	assert_eq(_npc.talk.quest, _quest, "then its card")
	assert_true(_npc.talk.offering)
	var card := _npc.card_menu as TalkCard
	assert_not_null(card.get_button("Accept"))
	assert_not_null(card.get_button("Not now"))
	assert_eq(card.get_quest_panel().get_goal_texts(), ["•  Deliver Kyrite  300"])
	assert_string_contains(card.get_quest_panel().get_extras(), "Reputation +1")
	var speech := _npc.bubble.content as SpeechBubble
	assert_eq(speech.get_line(), _quest.offer.lines[-1], "the offer's last line stays")
	card.get_button("Accept").pressed.emit()
	assert_null(_npc.talk.quest, "back to the list")
	assert_true(_ship.quests.is_accepted(_quest))
	assert_eq(_npc.get_choices()[0], _quest.steps[0].hand_in, "the step to hand in")


func test_not_now_leaves_it_offered() -> void:
	await _talk()
	_npc.talk.talk_about(_quest.offer)
	for line: String in _quest.offer.lines:
		_npc.talk.press()
	(_npc.card_menu as TalkCard).get_button("Not now").pressed.emit()
	assert_null(_npc.talk.quest)
	assert_false(_ship.quests.is_accepted(_quest))
	assert_has(_npc.get_choices(), _quest.offer, "still offered")


func test_hand_in_pays_the_rest_from_the_hold() -> void:
	_ship.quests.accept(_quest, [_player])
	_ship.store_haul({KYRITE: 200.0}, [_player])
	assert_eq(_ship.quests.goal_progress(_quest, 0), 200.0, "the haul paid in")
	assert_eq(_player.hold.amount(KYRITE), 0.0, "nothing left for the hold")
	_player.hold.add(KYRITE, 150.0)
	await _talk()
	assert_true(_npc.is_new(_quest.steps[0].hand_in), "ready: a dot")
	_npc.talk.press()
	assert_eq(_npc.talk.quest, _quest, "the step's card at once")
	assert_false(_npc.talk.offering)
	var card := _npc.card_menu as TalkCard
	assert_eq(card.get_quest_panel().get_goal_texts(), ["•  Deliver Kyrite  200 / 300"])
	var merisk_before: float = _player.hold.amount(MERISK)
	card.get_button("Hand in").pressed.emit()
	assert_eq(_player.hold.amount(KYRITE), 50.0, "the missing 100 from the hold")
	assert_eq(_player.hold.amount(MERISK), merisk_before + 2.0, "the reward")
	assert_eq(_ship.quests.reputation[&"quartermaster"], 1)
	assert_true(_ship.story.is_set(&"quest.ammo_run.kyrite"))
	assert_eq(_npc.talk.topic, _quest.steps[0].hand_in, "then they say its lines")
	assert_eq(_ship.quests.current_step(_quest), _quest.steps[1], "the next step")
	assert_false(_npc.get_choices().has(_quest.steps[1].hand_in), "handed in elsewhere")


func test_hand_in_waits_for_the_hold() -> void:
	_ship.quests.accept(_quest, [_player])
	await _talk()
	assert_false(_npc.is_new(_quest.steps[0].hand_in), "not ready: no dot")
	_npc.talk.press()
	var card := _npc.card_menu as TalkCard
	assert_true(card.get_button("Hand in").disabled)
	_npc.talk.press()
	assert_eq(_npc.talk.quest, _quest, "nothing happens")
	card.get_button("Back").pressed.emit()
	assert_null(_npc.talk.quest)


func _talk() -> void:
	_player.global_position = _npc.use_point.global_position + Vector3(0.0, 0.0, 1.0)
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	_npc.use_point.use(_player)
	await wait_process_frames(1)
