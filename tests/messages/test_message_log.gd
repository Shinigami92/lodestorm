extends GutTest
## The ship's messages (`MessageLog`, `StationWait`): the catalog's messages coming in on a return
## once their flags are set, heard to the end setting their flag, the calls from whoever waits at a
## station (once, not while docked there, not twice unheard, a line other than the last), the save,
## and the game's messages and call lines.

const DIRECTOR_TEST := preload("res://tests/story/test_story_director.gd")
const QUEST_LOG_TEST := preload("res://tests/quests/test_quest_log.gd")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")

var _log: MessageLog


func before_each() -> void:
	_log = MessageLog.new()
	_log.catalog = MessageCatalog.new()
	var director := StoryDirector.new()
	director.catalog = BeatCatalog.new()
	director.quests.catalog = QuestCatalog.new()
	director.quests.story = director.story
	_log.director = director
	_log.story = director.story


## A message `id` from `from`, coming in once `requires` are set.
static func make_message(
	id: StringName, from: StringName, requires: Array[StringName] = []
) -> Message:
	var message := Message.new()
	message.id = id
	message.from = from
	message.lines = ["%s, line one." % id, "%s, line two." % id]
	message.requires = requires
	return message


## Puts out a waiting beat carried by `npc` (its id `id`).
func _beat_waits(id: StringName, npc: StringName) -> Beat:
	var beat: Beat = DIRECTOR_TEST.make_beat(id, npc, 0, StringName("%s.%s_done" % [npc, id]))
	_log.director.catalog.beats.append(beat)
	_log.director.end_run(&"")
	assert_true(_log.director.is_waiting(beat), "the test's beat waits")
	return beat


func test_messages_come_in_once_their_flags_are_set() -> void:
	var open := make_message(&"open", &"councillor")
	var closed := make_message(&"closed", &"depot_master", [&"beat.news"])
	_log.catalog.messages = [open, closed]
	var came: Array[ReceivedMessage] = _log.come_in(&"torvane")
	assert_eq(came.size(), 1)
	assert_eq(came[0].message, open)
	assert_true(_log.come_in(&"torvane").is_empty(), "each once")
	_log.story.set_flag(&"beat.news")
	assert_eq(_log.come_in(&"ostra")[0].message, closed)
	assert_eq(_log.unheard(), 2)
	_log.hear(_log.received[0])
	assert_true(_log.story.is_set(&"message.open"), "heard to the end")
	assert_eq(_log.unheard(), 1)


func test_someone_waiting_at_a_station_calls_once() -> void:
	_beat_waits(&"news", &"councillor")
	assert_eq(_log.waits().size(), 1)
	assert_eq(_log.waits(&"ostra")[0].npc, &"councillor")
	assert_true(_log.waits(&"lisk").is_empty(), "only where they are")
	var came: Array[ReceivedMessage] = _log.come_in(&"torvane")
	assert_eq(came.size(), 1)
	assert_true(came[0].is_call())
	assert_eq(came[0].message.from, &"councillor")
	var selin: NpcProfile = NpcProfile.find(&"councillor")
	assert_has(selin.calls, came[0].message.lines[0], "one of her call lines")
	assert_true(_log.come_in(&"torvane").is_empty(), "once")
	assert_eq(_log.waits().size(), 1, "she still waits")


func test_no_call_while_docked_there_or_aboard() -> void:
	_beat_waits(&"news", &"councillor")
	_beat_waits(&"ship_news", &"engineer")
	assert_eq(_log.waits().size(), 1, "the engineer is aboard")
	assert_true(_log.come_in(&"ostra").is_empty(), "docked where she waits")
	assert_true(_log.come_in(&"torvane").is_empty(), "and not later either")


func test_no_second_call_while_one_is_unheard() -> void:
	_log.director.catalog.beats.append(DIRECTOR_TEST.make_beat(&"first", &"councillor"))
	_log.director.end_run(&"")
	var second: Beat = DIRECTOR_TEST.make_beat(&"second", &"councillor", 0, &"councillor.read")
	_log.director.catalog.beats.append(second)
	_log.director.end_run(&"")
	# The first one doesn't wait (no done_when), so it never calls; the second does.
	assert_eq(_log.come_in(&"torvane").size(), 1)
	var quest: Quest = QUEST_LOG_TEST.make_quest(&"ostra_run", &"councillor")
	_log.director.quests.catalog.quests.append(quest)
	_log.director.quests.accept(quest, [])
	_log.director.quests.take_from({KYRITE: 300.0})
	assert_eq(_log.waits().size(), 2, "her beat and her step")
	assert_true(_log.come_in(&"torvane").is_empty(), "her call is still unheard")
	assert_true(&"quest.ostra_run.kyrite" in _log.called, "the step doesn't call later")


func test_a_ready_step_calls_and_lines_change() -> void:
	var quest: Quest = QUEST_LOG_TEST.make_quest(&"depot_run", &"depot_master")
	_log.director.quests.catalog.quests.append(quest)
	_log.director.quests.accept(quest, [])
	_log.director.quests.take_from({KYRITE: 200.0})
	assert_true(_log.waits().is_empty(), "not all of it delivered")
	_log.director.quests.take_from({KYRITE: 100.0})
	var wait: StationWait = _log.waits()[0]
	assert_eq(wait.quest, quest)
	assert_eq(wait.key, &"quest.depot_run.kyrite")
	assert_eq(wait.station, &"ostra")
	var came: Array[ReceivedMessage] = _log.come_in(&"torvane")
	assert_eq(came.size(), 1)
	var last: int = came[0].call_line
	_log.hear(came[0])
	for i: int in 10:
		var other: Beat = _beat_waits(StringName("news_%d" % i), &"depot_master")
		var called: ReceivedMessage = _log.come_in(&"torvane")[0]
		assert_ne(called.call_line, last, "never the line of the last call")
		last = called.call_line
		_log.hear(called)
		_log.story.set_flag(other.done_when)


func test_saved_and_read_back() -> void:
	var message := make_message(&"open", &"councillor")
	_log.catalog.messages = [message]
	_beat_waits(&"news", &"bartender")
	_log.come_in(&"torvane")
	_log.hear(_log.received[0])
	var copy := MessageLog.new()
	copy.catalog = _log.catalog
	assert_true(copy.load_data(JSON.parse_string(JSON.stringify(_log.save_data()))))
	assert_eq(copy.received.size(), 2)
	assert_eq(copy.received[0].message, message)
	assert_true(copy.received[0].heard)
	assert_eq(copy.received[1].message.from, &"bartender")
	assert_eq(copy.received[1].message.lines, _log.received[1].message.lines)
	assert_false(copy.received[1].heard)
	assert_eq(copy.called, [&"beat.news"] as Array[StringName])


func test_broken_entries_are_skipped() -> void:
	var saved: Dictionary = {
		"received":
		[
			{"id": "gone", "heard": true},
			{"from": "councillor", "call": 99},
			{"from": "nobody", "call": 0},
			"nonsense",
			{"from": "councillor", "call": 1},
		],
		"called": ["beat.news", "not a flag", 3],
	}
	assert_false(_log.load_data(saved))
	assert_eq(_log.received.size(), 1, "only Selin's second line reads")
	assert_eq(_log.received[0].call_line, 1)
	assert_eq(_log.called, [&"beat.news"] as Array[StringName])
	assert_false(_log.load_data("nonsense"))
	assert_true(_log.load_data(null), "an older save without messages")


func test_every_message_and_call_keeps_to_the_scheme() -> void:
	for message: Message in MessageLog.CATALOG.messages:
		assert_true(Story.is_valid_flag(message.flag()), "%s: its flag" % message.id)
		assert_not_null(NpcProfile.find(message.from), "%s: who leaves it" % message.id)
		assert_false(message.lines.is_empty(), "%s: what it says" % message.id)
	for profile: NpcProfile in NpcProfile.all():
		if not profile.calls.is_empty():
			assert_false(profile.station.is_empty(), "%s calls from a station" % profile.id)
			assert_gt(profile.calls.size(), 1, "%s: calls to change between" % profile.id)
	for id: StringName in [&"councillor", &"depot_master", &"bartender", &"rival_captain"]:
		assert_eq(NpcProfile.find(id).calls.size(), 3, "%s: three call lines" % id)
