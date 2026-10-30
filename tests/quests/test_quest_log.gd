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
	first.reputation = 1
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
	_quest.requires_reputation = 2
	assert_true(_log.offered_by(&"quartermaster", [&"vehra"]).is_empty(), "no flag")
	_log.story.set_flag(&"quartermaster.ammo")
	assert_true(_log.offered_by(&"quartermaster", []).is_empty(), "the ship doesn't reach Vehra")
	assert_true(_log.offered_by(&"quartermaster", [&"vehra"]).is_empty(), "too little trust")
	_log.reputation[&"quartermaster"] = 2
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
	_log.reputation[&"quartermaster"] = 3
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_log.save_data()))
	var read := QuestLog.new()
	read.catalog = _log.catalog
	assert_true(read.load_data(saved))
	assert_true(read.is_accepted(_quest))
	assert_eq(read.goal_progress(_quest, 0), 120.0)
	assert_eq(read.reputation[&"quartermaster"], 3)
	assert_true(read.load_data(null), "nothing saved changes nothing")


func test_unknown_quests_are_skipped() -> void:
	var read := QuestLog.new()
	read.catalog = _log.catalog
	assert_false(
		read.load_data({"accepted": ["gone", "ammo_run"], "progress": {"gone": [1]}}), "skipped"
	)
	assert_eq(read.accepted, [&"ammo_run"] as Array[StringName])
	assert_false(read.progress.has(&"gone"))
