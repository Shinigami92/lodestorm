extends GutTest
## The story director (`StoryDirector`): which beat goes out on a return, how beats wait, each kind
## of condition, the save, and the game's beats (`game/story/beats.tres`).

const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const SYSTEM: StarSystem = preload("res://game/world/star_system.tres")
const QUEST_LOG_TEST := preload("res://tests/quests/test_quest_log.gd")

var _director: StoryDirector


func before_each() -> void:
	_director = StoryDirector.new()
	_director.catalog = BeatCatalog.new()
	_director.quests.story = _director.story


## A beat `id` of `npc`'s with `priority`, waiting for `done_when`, under `conditions`.
static func make_beat(
	id: StringName,
	npc: StringName = &"",
	priority: int = 0,
	done_when: StringName = &"",
	conditions: Array[BeatCondition] = []
) -> Beat:
	var beat := Beat.new()
	beat.id = id
	beat.npc = npc
	beat.priority = priority
	beat.done_when = done_when
	beat.conditions = conditions
	return beat


func _flags(flags: Array[StringName], unless: Array[StringName] = []) -> FlagCondition:
	var condition := FlagCondition.new()
	condition.flags = flags
	condition.unless = unless
	return condition


func test_the_best_beat_goes_out_on_a_return() -> void:
	var low: Beat = make_beat(&"low", &"", 1)
	var high: Beat = make_beat(&"high", &"", 5)
	var closed: Beat = make_beat(&"closed", &"", 9, &"", [_flags([&"pilot.course"])])
	_director.catalog.beats = [low, closed, high]
	watch_signals(_director)
	assert_eq(_director.end_run(&""), [high] as Array[Beat], "the highest whose conditions hold")
	assert_true(_director.story.is_set(&"beat.high"), "its flag")
	assert_signal_emitted_with_parameters(_director, "beat_put_out", [high])
	assert_eq(_director.end_run(&""), [low] as Array[Beat], "one per return, each once")
	assert_eq(_director.end_run(&""), [] as Array[Beat], "nothing left")
	_director.story.set_flag(&"pilot.course")
	assert_eq(_director.dock(&"ostra"), [closed] as Array[Beat], "a docking is a return too")
	assert_eq(_director.runs, 3, "dockings aren't runs")


func test_per_return_is_the_one_setting() -> void:
	_director.catalog.beats = [make_beat(&"one"), make_beat(&"two"), make_beat(&"three")]
	_director.per_return = 0
	assert_true(_director.end_run(&"").is_empty(), "none")
	_director.per_return = 2
	assert_eq(_director.end_run(&"").size(), 2)


func test_beats_wait_until_done() -> void:
	var first: Beat = make_beat(&"first", &"pilot", 0, &"pilot.first")
	var second: Beat = make_beat(&"second", &"engineer", 0, &"engineer.second")
	var third: Beat = make_beat(&"third", &"quartermaster", 0, &"quartermaster.third")
	_director.catalog.beats = [first, second, third]
	_director.end_run(&"")
	_director.end_run(&"")
	assert_eq(_director.waiting(), [first, second] as Array[Beat])
	assert_eq(StoryDirector.MOST_WAITING, 2, "the test assumes two")
	assert_true(_director.end_run(&"").is_empty(), "no more while two wait")
	_director.story.set_flag(&"pilot.first")
	assert_false(_director.is_waiting(first), "done")
	assert_eq(_director.end_run(&""), [third] as Array[Beat])


func test_one_beat_waits_per_npc() -> void:
	var first: Beat = make_beat(&"first", &"pilot", 5, &"pilot.first")
	var second: Beat = make_beat(&"second", &"pilot", 4, &"pilot.second")
	var other: Beat = make_beat(&"other", &"engineer", 1)
	_director.catalog.beats = [first, second, other]
	_director.end_run(&"")
	assert_eq(_director.end_run(&""), [other] as Array[Beat], "the pilot has one waiting")
	_director.story.set_flag(&"pilot.first")
	assert_eq(_director.end_run(&""), [second] as Array[Beat])


func test_returns_and_places() -> void:
	var docking: Beat = make_beat(&"docking", &"", 2)
	docking.returns = Beat.Returns.DOCKING
	docking.at = &"ostra"
	var run: Beat = make_beat(&"run", &"", 1)
	run.returns = Beat.Returns.RUN
	run.at = &"tessar"
	_director.catalog.beats = [docking, run]
	assert_true(_director.end_run(&"ostra").is_empty(), "a run back at Ostra? not a docking")
	assert_true(_director.dock(&"pell").is_empty(), "another station")
	assert_eq(_director.dock(&"ostra"), [docking] as Array[Beat])
	assert_true(_director.end_run(&"vehra").is_empty(), "another body")
	assert_eq(_director.end_run(&"tessar"), [run] as Array[Beat])


func test_a_repeating_beat_comes_again() -> void:
	var request: Beat = make_beat(&"request")
	request.repeats = true
	request.done_when = &"depot_master.request"
	var since := RunsCondition.new()
	since.runs = 2
	since.since = RunsCondition.Since.THIS_BEAT
	request.conditions = [since]
	_director.catalog.beats = [request]
	assert_true(_director.end_run(&"").is_empty(), "one run")
	assert_eq(_director.end_run(&"").size(), 1, "two runs since the start")
	assert_false(_director.is_waiting(request), "repeating beats never wait")
	assert_true(_director.end_run(&"").is_empty())
	assert_eq(_director.end_run(&"").size(), 1, "two runs since it came")


func test_runs_since_any_beat() -> void:
	var big: Beat = make_beat(&"big", &"", 9)
	var since := RunsCondition.new()
	since.runs = 3
	big.conditions = [since]
	var small: Beat = make_beat(&"small", &"", 0)
	small.repeats = true
	_director.catalog.beats = [big, small]
	assert_eq(_director.end_run(&""), [small] as Array[Beat])
	assert_eq(_director.runs_since(), 0)
	_director.per_return = 0
	_director.end_run(&"")
	_director.end_run(&"")
	_director.per_return = 1
	assert_eq(_director.end_run(&""), [big] as Array[Beat], "three runs without a beat")


func test_flag_and_quest_conditions() -> void:
	var flags: FlagCondition = _flags([&"pilot.course"], [&"crew.dace.joined"])
	var beat: Beat = make_beat(&"beat")
	assert_false(flags.holds(_director, beat))
	_director.story.set_flag(&"pilot.course")
	assert_true(flags.holds(_director, beat))
	_director.story.set_flag(&"crew.dace.joined")
	assert_false(flags.holds(_director, beat), "unless")
	var quest: Quest = QUEST_LOG_TEST.make_quest(&"ammo_run", &"quartermaster")
	_director.quests.catalog = QuestCatalog.new()
	_director.quests.catalog.quests = [quest]
	var active := QuestCondition.new()
	active.quest = &"ammo_run"
	active.step = &"vyrel"
	var done := QuestCondition.new()
	done.quest = &"ammo_run"
	done.step = &"kyrite"
	done.state = QuestCondition.State.DONE
	var whole := QuestCondition.new()
	whole.quest = &"ammo_run"
	assert_false(whole.holds(_director, beat), "not accepted")
	_director.quests.accept(quest, [])
	assert_true(whole.holds(_director, beat), "accepted")
	assert_false(active.holds(_director, beat), "the first step is active")
	_director.story.set_flag(quest.step_flag(quest.steps[0]))
	assert_true(active.holds(_director, beat))
	assert_true(done.holds(_director, beat))


func test_act_shield_and_reputation_conditions() -> void:
	var beat: Beat = make_beat(&"beat")
	var act := ActCondition.new()
	act.from = 2
	act.to = 3
	assert_false(act.holds(_director, beat), "act 1")
	_director.heat_shield.install_next()
	assert_eq(_director.act(), 2)
	assert_true(act.holds(_director, beat))
	var third := ShieldCondition.new()
	third.paid = 0.33
	assert_false(third.holds(_director, beat))
	var plate: ShieldPlate = _director.heat_shield.next_plate()
	var share: Dictionary[OreType, float] = {}
	for ore_type: OreType in plate.cost:
		share[ore_type] = plate.cost[ore_type] * 0.4
	_director.heat_shield.take_from(share)
	assert_almost_eq(_director.heat_shield.paid_share(), 0.4, 0.001)
	assert_true(third.holds(_director, beat))
	var trust := ReputationCondition.new()
	trust.npc = &"quartermaster"
	trust.pips = 2
	assert_false(trust.holds(_director, beat))
	_director.quests.reputation[&"quartermaster"] = 2
	assert_true(trust.holds(_director, beat))


func test_ore_region_and_fall_conditions() -> void:
	var ore := OreFoundCondition.new()
	ore.ore = KYRITE
	var region := RegionVisitedCondition.new()
	region.region = &"redscar"
	var fall := FallCondition.new()
	var fallen: Beat = make_beat(&"fallen", &"", 0, &"", [fall])
	_director.catalog.beats = [fallen]
	assert_false(ore.holds(_director, fallen))
	_director.find_ore(KYRITE)
	assert_true(ore.holds(_director, fallen))
	assert_false(region.holds(_director, fallen))
	_director.start_run(SYSTEM.region_by_id(&"redscar"))
	assert_true(region.holds(_director, fallen))
	assert_true(_director.end_run(&"").is_empty(), "nobody fell")
	_director.start_run(null)
	_director.count_fall()
	assert_eq(_director.end_run(&""), [fallen] as Array[Beat])
	assert_eq(_director.falls, 0, "only while its return is directed")


func test_saved_and_read_back() -> void:
	var beat: Beat = make_beat(&"beat")
	_director.catalog.beats = [beat]
	_director.end_run(&"")
	_director.end_run(&"")
	_director.find_ore(KYRITE)
	_director.start_run(SYSTEM.region_by_id(&"mire"))
	var saved: Variant = JSON.parse_string(JSON.stringify(_director.save_data()))
	var read := StoryDirector.new()
	read.catalog = _director.catalog
	assert_true(read.load_data(saved))
	assert_eq(read.runs, 2)
	assert_eq(read.last_beat, 1, "put out on the first run's return")
	assert_eq(read.put_out, {&"beat": 1} as Dictionary[StringName, int])
	assert_eq(read.ores_found, [KYRITE] as Array[OreType])
	assert_eq(read.regions_visited, [&"mire"] as Array[StringName])
	assert_true(read.load_data(null), "nothing saved")


func test_broken_entries_are_skipped() -> void:
	_director.catalog.beats = [make_beat(&"beat")]
	var saved: Dictionary = {
		"runs": 3,
		"last_beat": 9,
		"put_out": {"beat": 1, "gone": 2},
		"ores": ["uid://nothing"],
		"regions": ["redscar", 4],
	}
	assert_false(_director.load_data(saved))
	assert_eq(_director.last_beat, 3, "never after the runs")
	assert_eq(_director.put_out, {&"beat": 1} as Dictionary[StringName, int])
	assert_true(_director.ores_found.is_empty())
	assert_eq(_director.regions_visited, [&"redscar"] as Array[StringName])
	assert_false(_director.load_data("broken"))


## The game's beats: ids that save, NPCs and places that exist, waits that can end.
func test_every_beat_keeps_to_the_scheme() -> void:
	var npcs: Array[StringName] = []
	for profile: NpcProfile in NpcProfile.all():
		npcs.append(profile.id)
	assert_gt(npcs.size(), 0)
	var ids: Array[StringName] = []
	for beat: Beat in StoryDirector.CATALOG.beats:
		var what: String = String(beat.id)
		assert_true(Story.is_valid_flag(beat.flag()), "%s: its id" % what)
		assert_does_not_have(ids, beat.id, "%s: once" % what)
		ids.append(beat.id)
		if not beat.npc.is_empty():
			assert_has(npcs, beat.npc, "%s: its NPC" % what)
		if not beat.at.is_empty():
			assert_not_null(SYSTEM.body_by_id(beat.at), "%s: where" % what)
		if not beat.done_when.is_empty():
			assert_true(Story.is_valid_flag(beat.done_when), "%s: its wait's flag" % what)
		assert_false(
			beat.repeats and not beat.done_when.is_empty(), "%s: a repeat never waits" % what
		)
		for condition: BeatCondition in beat.conditions:
			assert_not_null(condition, "%s: its conditions" % what)
