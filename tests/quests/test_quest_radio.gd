extends GutTest
## The quests' calls over the radio (`QuestRadio`): the landing line once per step, a goal done
## out there (counted, or its fragments picked up) or aboard, the step's ready line instead of the
## last goal's, worded for one player or several, said again at the NPC before the step's card,
## saved with the quests and forgotten at the hand-in.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const PLAYER_SCENE: String = "res://game/player/player.tscn"
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const REGION: StringName = &"redscar"
const LANDING: String = "Two nests in Redscar. Watch yourself."
const LANDING_COOP: String = "Two nests in Redscar. Watch each other's backs."
const NESTS_DONE: String = "That's both nests."
const FRAGMENTS_DONE: String = "That's every fragment. Keep them safe."
const READY: String = "That's all of it. Come back to me."
const KYRITE_DONE: String = "That's the Kyrite."

var _map: Node3D
var _ship: Ship
var _player: Player
var _npc: Npc
var _quest: Quest


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	var ship := _map.get_node("Ship") as Ship
	# Past his tour's offer and his greeting: the list shows at once.
	ship.story.set_flag(&"quartermaster.tour_offer")
	ship.story.set_flag(&"quartermaster.greeting")
	_quest = _make_quest()
	ship.quests.catalog = QuestCatalog.new()
	ship.quests.catalog.quests = [_quest]
	add_child_autofree(_map)
	_ship = ship
	_player = _map.get_node("Player") as Player
	_npc = _ship.get_node("Rooms/Lower/Armory/Quartermaster") as Npc
	await wait_physics_frames(2)
	_ship.quests.accept(_quest, [_player])


## Brannik's quest: clear two nests (landing and done lines) and recover two fragments (a done
## line) in `REGION`, ready with a line of its own; then deliver Kyrite (a done line).
static func _make_quest() -> Quest:
	var nests := ClearNestsGoal.new()
	nests.region = REGION
	nests.amount = 2
	nests.landing_line = _line(LANDING, LANDING_COOP)
	nests.done_line = _line(NESTS_DONE)
	var fragments := RecoverFragmentsGoal.new()
	fragments.region = REGION
	fragments.amount = 2
	fragments.done_line = _line(FRAGMENTS_DONE)
	var field := QuestStep.new()
	field.id = &"field"
	field.goals = [nests, fragments]
	field.ready_line = _line(READY)
	field.hand_in = _topic(&"quartermaster.radio_test_field", "The field")
	var deliver := DeliverGoal.new()
	deliver.item = KYRITE
	deliver.amount = 10
	deliver.done_line = _line(KYRITE_DONE)
	var kyrite := QuestStep.new()
	kyrite.id = &"kyrite"
	kyrite.goals = [deliver]
	kyrite.hand_in = _topic(&"quartermaster.radio_test_kyrite", "The Kyrite")
	var quest := Quest.new()
	quest.id = &"radio_test"
	quest.title = "Radio test"
	quest.giver = &"quartermaster"
	quest.steps = [field, kyrite]
	return quest


static func _line(text: String, coop_text: String = "") -> RadioLine:
	var line := RadioLine.new()
	line.text = text
	line.coop_text = coop_text
	return line


static func _topic(id: StringName, title: String) -> Topic:
	var topic := Topic.new()
	topic.id = id
	topic.title = title
	topic.lines = ["%s, thanks." % title]
	return topic


func test_the_landing_line_once_per_step_from_its_npc() -> void:
	_ship.quest_radio.land(QuestVisit.new(_ship.quests, REGION))
	assert_eq(_caller(), "Brannik · Radio")
	assert_eq(_player.radio.get_line(), LANDING)
	await _until_quiet()
	_ship.quest_radio.land(QuestVisit.new(_ship.quests, REGION))
	assert_eq(_player.radio.get_line(), "", "not on the next visit")
	_ship.quest_radio.land(QuestVisit.new(_ship.quests, &"hollow_mire"))
	assert_eq(_player.radio.get_line(), "", "nothing open there")


func test_together_the_coop_wording() -> void:
	_add_teammate()
	_ship.quest_radio.land(QuestVisit.new(_ship.quests, REGION))
	assert_eq(_player.radio.get_line(), LANDING_COOP)


func test_goals_done_out_there_then_ready() -> void:
	var visit := QuestVisit.new(_ship.quests, REGION)
	_ship.quest_radio._on_player_left(_player)
	_ship.quest_radio.land(visit)
	await _until_quiet()
	var nests: QuestVisit.Entry = visit.entries[0]
	var fragments: QuestVisit.Entry = visit.entries[1]
	visit.count(nests)
	assert_eq(_player.radio.get_line(), "", "one nest of two")
	visit.count(nests)
	assert_eq(_player.radio.get_line(), NESTS_DONE)
	await _until_quiet()
	_player.quest_pack.add(fragments)
	assert_eq(_player.radio.get_line(), "", "one fragment of two")
	_player.quest_pack.add(fragments)
	assert_eq(_player.radio.get_line(), READY, "picked up, all done: the step's line instead")
	assert_eq(_ship.quests.goal_progress(_quest, 1), 0.0, "counting once aboard")
	await _until_quiet()
	visit.count_carried(_player.quest_pack.take_all())
	visit.commit()
	assert_eq(_player.radio.get_line(), "", "called out there already")
	var step: QuestStep = _quest.steps[0]
	assert_eq(_ship.quests.calls.lines(_quest, step, false), [LANDING, NESTS_DONE, READY])
	# The pack's fragment looks go at the end of the frame.
	await wait_process_frames(1)


func test_a_goal_done_aboard_and_the_calls_forgotten_at_the_hand_in() -> void:
	var visit := QuestVisit.new(_ship.quests, REGION)
	_ship.quest_radio.land(visit)
	await _until_quiet()
	visit.count(visit.entries[0], 2.0)
	visit.count(visit.entries[1], 2.0)
	visit.commit()
	await _until_quiet()
	assert_true(_ship.quests.hand_in(_quest, _player, [_player]))
	var kyrite: QuestStep = _quest.steps[1]
	assert_eq(_ship.quests.calls.lines(_quest, kyrite, false), [] as Array[String], "a new step")
	_ship.quests.take_from({KYRITE: 4.0})
	assert_eq(_player.radio.get_line(), "", "not done yet")
	_ship.quests.take_from({KYRITE: 20.0})
	assert_eq(_player.radio.get_line(), KYRITE_DONE)


func test_said_again_at_the_npc_before_the_card() -> void:
	_ship.quest_radio.land(QuestVisit.new(_ship.quests, REGION))
	await _until_quiet()
	_player.global_position = _npc.use_point.global_position + Vector3(0.0, 0.0, 1.0)
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	_npc.use_point.use(_player)
	await wait_process_frames(1)
	assert_eq(_npc.get_choices()[0], _quest.steps[0].hand_in)
	_npc.talk.press()
	assert_eq(_npc.talk.get_topic_lines(), [LANDING] as Array[String])
	assert_null(_npc.talk.quest)
	_npc.talk.press()
	assert_eq(_npc.talk.quest, _quest, "then its card")
	assert_false(_ship.story.is_set(_quest.steps[0].hand_in.id), "not heard as the hand-in")


func test_saved_and_read_back() -> void:
	_ship.quest_radio.land(QuestVisit.new(_ship.quests, REGION))
	var read := QuestLog.new()
	read.catalog = _ship.quests.catalog
	assert_true(read.load_data(_ship.quests.save_data()))
	assert_eq(read.calls.lines(_quest, _quest.steps[0], false), [LANDING] as Array[String])


func test_spoken_by_the_npc_it_is_handed_in_at() -> void:
	var lines: PackedStringArray = _quest.spoken_lines()[&"quartermaster"]
	for text: String in [LANDING, LANDING_COOP, NESTS_DONE, FRAGMENTS_DONE, READY, KYRITE_DONE]:
		assert_has(lines, text)


## Who the local player's radio bubble says is calling, or "" while it shows nothing.
func _caller() -> String:
	var bubble := _player.radio.panel.content as RadioBubble
	return bubble.get_caller() if _player.radio.panel.visible else ""


## Waits until the radio is quiet and nothing waits.
func _until_quiet() -> void:
	for i: int in 3000:
		if _player.radio.get_line().is_empty() and _player.radio.waiting_count() == 0:
			break
		await wait_physics_frames(1)
	await wait_seconds(PlayerRadio.GAP + 0.1)


## A teammate (player 2, not local) next to the player.
func _add_teammate() -> Player:
	var teammate := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	teammate.local = false
	teammate.number = 2
	_player.get_parent().add_child(teammate)
	teammate.global_position = _player.global_position + _player.global_basis.x * 2.5
	teammate.reset_physics_interpolation()
	return teammate
