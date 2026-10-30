extends GutTest
## The ship's quests (`QuestLog`): offering, accepting, the goals counting and the save.

const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
const MERISK: AlloyType = preload("res://game/refinery/alloys/alloy_merisk.tres")

var _log: QuestLog
var _quest: Quest


func before_each() -> void:
	_quest = make_quest(&"ammo_run", &"quartermaster")
	_log = QuestLog.new()
	_log.catalog = QuestCatalog.new()
	_log.catalog.quests = [_quest]


## A quest of `giver`'s: deliver 300 Kyrite, then mine 100 Vyrel in one run (handed in at the
## engineer).
static func make_quest(id: StringName, giver: StringName) -> Quest:
	var quest := Quest.new()
	quest.id = id
	quest.title = "Ammo run"
	quest.giver = giver
	quest.offer = _topic(StringName("%s.job_%s" % [giver, id]), "About that job...")
	var deliver := DeliverGoal.new()
	deliver.item = KYRITE
	deliver.amount = 300
	var first := QuestStep.new()
	first.id = &"kyrite"
	first.text = "Bring 300 Kyrite."
	first.goals = [deliver]
	first.hand_in = _topic(StringName("%s.job_%s_kyrite" % [giver, id]), "The Kyrite")
	first.items = {MERISK: 2}
	var mine := MineGoal.new()
	mine.ore = VYREL
	mine.amount = 100
	var second := QuestStep.new()
	second.id = &"vyrel"
	second.text = "Mine 100 Vyrel in one run."
	second.goals = [mine]
	second.hand_in_to = &"engineer"
	second.hand_in = _topic(StringName("engineer.job_%s_vyrel" % id), "The Vyrel")
	quest.steps = [first, second]
	return quest


static func _topic(id: StringName, title: String) -> Topic:
	var topic := Topic.new()
	topic.id = id
	topic.title = title
	topic.lines = ["%s, line one." % title, "%s, line two." % title]
	return topic


func test_offered_by_its_giver_until_accepted() -> void:
	assert_eq(_log.offered_by(&"quartermaster", []), [_quest])
	assert_eq(_log.offered_by(&"engineer", []), [] as Array[Quest], "only the giver")
	assert_eq(_log.quest_for(_quest.offer), _quest)
	assert_true(_log.accept(_quest, []))
	assert_false(_log.accept(_quest, []), "once")
	assert_eq(_log.offered_by(&"quartermaster", []), [] as Array[Quest], "accepted")
	assert_eq(_log.current_step(_quest), _quest.steps[0])
	assert_eq(_log.steps_at(&"quartermaster"), [_quest], "handed in at the giver")
	assert_eq(_log.quest_for(_quest.steps[0].hand_in), _quest)


func test_offered_once_its_conditions_hold() -> void:
	_quest.requires = [&"quartermaster.ammo"]
	_quest.requires_body = &"vehra"
	assert_true(_log.offered_by(&"quartermaster", [&"vehra"]).is_empty(), "no flag")
	_log.story.set_flag(&"quartermaster.ammo")
	assert_true(_log.offered_by(&"quartermaster", []).is_empty(), "the ship doesn't reach Vehra")
	assert_eq(_log.offered_by(&"quartermaster", [&"vehra"]), [_quest])


func test_hauls_fill_the_deliveries_in_accepted_order() -> void:
	var other: Quest = make_quest(&"second_run", &"quartermaster")
	_log.catalog.quests.append(other)
	_log.accept(_quest, [])
	_log.accept(other, [])
	var taken: Dictionary[OreType, float] = _log.take_from({KYRITE: 250.0, VYREL: 40.0})
	assert_eq(taken, {KYRITE: 250.0} as Dictionary[OreType, float], "Vyrel isn't asked for")
	assert_eq(_log.goal_progress(_quest, 0), 250.0)
	assert_eq(_log.goal_progress(other, 0), 0.0, "the first accepted fills first")
	taken = _log.take_from({KYRITE: 100.0})
	assert_eq(taken[KYRITE], 100.0)
	assert_eq(_log.goal_progress(_quest, 0), 300.0, "full")
	assert_eq(_log.goal_progress(other, 0), 50.0, "the rest goes on")
	assert_eq(_log.missing(other), {KYRITE: 250} as Dictionary[ItemType, int])


func test_nothing_is_taken_without_an_active_delivery() -> void:
	assert_true(_log.take_from({KYRITE: 100.0}).is_empty(), "not accepted")


func test_mining_counts_the_best_run() -> void:
	_log.accept(_quest, [])
	_log.story.set_flag(_quest.step_flag(_quest.steps[0]))
	assert_eq(_log.current_step(_quest), _quest.steps[1])
	assert_eq(_log.steps_at(&"engineer"), [_quest], "handed in at the engineer")
	_log.start_run()
	_log.count_hauled(VYREL, 30.0)
	_log.count_hauled(VYREL, 40.0)
	assert_eq(_log.goal_progress(_quest, 0), 70.0, "one run adds up")
	_log.start_run()
	_log.count_hauled(VYREL, 50.0)
	assert_eq(_log.goal_progress(_quest, 0), 70.0, "a smaller run doesn't count")
	_log.count_hauled(VYREL, 80.0)
	assert_eq(_log.goal_progress(_quest, 0), 100.0, "done, never above")


func test_a_step_needs_its_goals_or_the_hold_for_deliveries() -> void:
	var hold := PlayerHold.new()
	_log.accept(_quest, [])
	assert_false(_log.can_hand_in(_quest, hold), "nothing delivered, nothing in the hold")
	hold.add(KYRITE, 299.0)
	assert_false(_log.can_hand_in(_quest, hold), "one short")
	_log.take_from({KYRITE: 1.0})
	assert_true(_log.can_hand_in(_quest, hold), "the hold pays the rest")
	_log.story.set_flag(_quest.step_flag(_quest.steps[0]))
	_log.progress[_quest.id] = PackedFloat64Array([0.0])
	hold.add(VYREL, 500.0)
	assert_false(_log.can_hand_in(_quest, hold), "mining can't be paid from the hold")


func test_saved_and_read_back() -> void:
	_log.accept(_quest, [])
	_log.take_from({KYRITE: 120.0})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_log.save_data()))
	var read := QuestLog.new()
	read.catalog = _log.catalog
	assert_true(read.load_data(saved))
	assert_true(read.is_accepted(_quest))
	assert_eq(read.goal_progress(_quest, 0), 120.0)
	assert_true(read.load_data(null), "nothing saved changes nothing")


func test_unknown_quests_are_skipped() -> void:
	var read := QuestLog.new()
	read.catalog = _log.catalog
	assert_false(
		read.load_data({"accepted": ["gone", "ammo_run"], "progress": {"gone": [1]}}), "skipped"
	)
	assert_eq(read.accepted, [&"ammo_run"] as Array[StringName])
	assert_false(read.progress.has(&"gone"))


func test_tracking_follows_the_first_accepted_then_the_main_quest() -> void:
	var main: Quest = make_quest(&"main_job", &"councillor")
	main.kind = Quest.Kind.MAIN
	_log.catalog.quests.append(main)
	assert_null(_log.get_tracked())
	assert_false(_log.track(_quest), "not accepted")
	_log.accept(_quest, [])
	assert_eq(_log.get_tracked(), _quest, "the first one accepted")
	_log.accept(main, [])
	assert_eq(_log.get_tracked(), _quest, "kept")
	assert_true(_log.track(main))
	assert_eq(_log.get_tracked(), main)
	assert_true(_log.track(_quest))
	var payer: Player = autofree(Player.new())
	_log.take_from({KYRITE: 300.0})
	assert_true(_log.hand_in(_quest, payer, []))
	assert_eq(_log.get_tracked(), _quest, "still a step to do")
	_log.start_run()
	_log.count_hauled(VYREL, 100.0)
	assert_true(_log.hand_in(_quest, payer, []))
	assert_eq(_log.get_tracked(), main, "done: the main quest")
	assert_false(_log.track(_quest), "done")


func test_tracked_saved_and_read_back() -> void:
	_log.accept(_quest, [])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_log.save_data()))
	var read := QuestLog.new()
	read.catalog = _log.catalog
	assert_true(read.load_data(saved))
	assert_eq(read.get_tracked(), _quest)
	var stale := QuestLog.new()
	stale.catalog = _log.catalog
	assert_false(stale.load_data({"accepted": [], "tracked": "ammo_run"}), "not accepted")
	assert_null(stale.get_tracked())


## A request of the depot master's: deliver 300 Kyrite (one step).
static func make_request(id: StringName) -> Quest:
	var request: Quest = make_quest(id, &"depot_master")
	request.kind = Quest.Kind.REQUEST
	request.steps.resize(1)
	return request


func test_a_step_lights_furnaces_and_opens_cradles() -> void:
	_quest.steps[0].furnaces = 2
	_quest.steps[0].cradles = 1
	_log.accept(_quest, [])
	_log.take_from({KYRITE: 300.0})
	var payer: Player = autofree(Player.new())
	assert_true(_log.hand_in(_quest, payer, []))
	assert_eq(_log.furnaces.unlocked, 2)
	assert_eq(_log.cradles.open, Cradles.START + 1)


func test_requests_come_back_in_turn() -> void:
	var requests: Array[Quest] = [make_request(&"r1"), make_request(&"r2"), make_request(&"r3")]
	_log.catalog.quests.append_array(requests)
	var payer: Player = autofree(Player.new())
	assert_eq(_log.offered_by(&"depot_master", [], 2), requests.slice(0, 2), "two open")
	assert_true(_log.accept(requests[0], []))
	assert_eq(_log.offered_by(&"depot_master", [], 2), requests.slice(1, 2), "one accepted")
	_log.take_from({KYRITE: 300.0})
	assert_true(_log.hand_in(requests[0], payer, []))
	assert_false(_log.is_accepted(requests[0]), "offered again later")
	assert_false(_log.story.is_set(requests[0].flag()))
	assert_eq(_log.offered_by(&"depot_master", [], 2), requests.slice(1, 3), "the next ones")
	_log.accept(requests[2], [])
	_log.take_from({KYRITE: 300.0})
	assert_true(_log.hand_in(requests[2], payer, []))
	assert_eq(_log.offered_by(&"depot_master", [], 2), requests.slice(0, 2), "from the first again")
	assert_eq(_log.offered_by(&"quartermaster", [], 2), [_quest], "a quest isn't a request")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_log.save_data()))
	var read := QuestLog.new()
	read.catalog = _log.catalog
	assert_true(read.load_data(saved))
	assert_eq(read.last_requests[&"depot_master"], &"r3")
