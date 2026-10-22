extends GutTest
## Upgrade levels and skill ranks taking real time (see docs/planned/refinery.md, Upgrades and
## skills take real time).

const TEST_MAP := preload("res://tests/support/test_map.gd")
const SKILL_TREE: SkillTree = preload("res://game/progression/skills/tree/skill_tree.tres")
const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const DASH: Skill = preload("res://game/progression/skills/tree/dash.tres")
const RELOAD_ON_THE_MOVE: Skill = preload(
	"res://game/progression/skills/tree/reload_on_the_move.tres"
)
const SUIT: Skill = preload("res://game/progression/skills/tree/reinforced_suit.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")

var _map: Node3D
var _player: Player
var _ship: Ship


func test_every_skill_rank_takes_time() -> void:
	for skill: Skill in SKILL_TREE.get_skills():
		var slower: float = 0.0
		for rank: SkillRank in skill.ranks:
			assert_gt(rank.seconds, slower, "%s: each rank takes longer" % skill.display_name)
			slower = rank.seconds


func test_a_job_runs_on_the_wall_clock() -> void:
	var job := TimedJob.new(3, 1000.0, 60.0)
	assert_false(job.is_done(1030.0))
	assert_almost_eq(job.progress(1030.0), 0.5, 0.001)
	assert_eq(job.time_left(1030.0), 30.0)
	assert_eq(job.progress(900.0), 0.0, "a clock set back waits")
	assert_eq(job.time_left(900.0), 60.0)
	assert_true(job.is_done(1060.0))
	assert_eq(job.progress(2000.0), 1.0)


func test_a_level_takes_effect_once_done() -> void:
	var upgrades := Upgrades.new()
	watch_signals(upgrades)
	assert_true(upgrades.start(ARMOR, 1000.0))
	assert_signal_emitted(upgrades, "changed")
	assert_eq(upgrades.mk(ARMOR), 1, "not yet")
	assert_false(upgrades.start(ARMOR, 1000.0), "one level at a time")
	assert_eq(upgrades.get_job(ARMOR).level, 2)
	assert_eq(upgrades.get_job(ARMOR).seconds, ARMOR.levels[0].seconds)
	assert_true(upgrades.start(DRILL, 1000.0), "any number of upgrades at once")
	var done: Array[Upgrade] = upgrades.update(1000.0 + ARMOR.levels[0].seconds - 1.0)
	assert_true(done.is_empty())
	done = upgrades.update(1000.0 + ARMOR.levels[0].seconds)
	assert_eq(done, [ARMOR, DRILL] as Array[Upgrade])
	assert_signal_emitted_with_parameters(upgrades, "finished", [DRILL])
	assert_eq(upgrades.mk(ARMOR), 2)
	assert_false(upgrades.is_running(ARMOR))
	assert_true(upgrades.start(ARMOR, 5000.0))
	assert_eq(upgrades.get_job(ARMOR).seconds, ARMOR.levels[1].seconds, "MK3 takes longer")


func test_stopping_gives_the_cost_back() -> void:
	var upgrades := Upgrades.new()
	assert_true(upgrades.stop(ARMOR).is_empty(), "nothing under way")
	upgrades.start(ARMOR, 0.0)
	assert_eq(upgrades.stop(ARMOR), ARMOR.cost_of(2))
	assert_false(upgrades.is_running(ARMOR))
	var skills := Skills.new()
	skills.ranks[SUIT] = 1
	skills.start(SUIT, 0.0)
	assert_eq(skills.stop(SUIT), SUIT.ranks[1].cost)
	assert_eq(skills.rank(SUIT), 1)


func test_a_skill_opens_once_the_rank_before_is_done() -> void:
	var skills := Skills.new()
	assert_false(skills.start(RELOAD_ON_THE_MOVE, 0.0))
	assert_true(skills.start(DASH, 0.0))
	assert_false(skills.is_open(RELOAD_ON_THE_MOVE), "dash is still under way")
	assert_eq(skills.finish_all(), [DASH] as Array[Skill])
	assert_true(skills.start(RELOAD_ON_THE_MOVE, 0.0))


func test_a_saved_job_must_be_the_next_level() -> void:
	var upgrades := Upgrades.new()
	assert_false(upgrades.restore(ARMOR, TimedJob.new(3, 0.0, 60.0)))
	assert_true(upgrades.restore(ARMOR, TimedJob.new(2, 0.0, 60.0)))
	upgrades.raise(ARMOR)
	assert_false(upgrades.is_running(ARMOR), "raised past it at once (the debug overlay)")


func test_station_starts_and_stops_a_level() -> void:
	await _load_map()
	var station: UpgradeStation = await _open_station("Armor")
	var card := station.card_menu as UpgradeCard
	_player.hold.add(KYRITE, 1000.0)
	_player.hold.add(VYREL, 1000.0)
	await wait_process_frames(1)
	assert_eq(card.get_time().text, "Takes %s" % FurnaceCard.duration_text(ARMOR.levels[0].seconds))
	assert_true(card.press_primary())
	assert_true(_player.upgrades.is_running(ARMOR))
	assert_true(_player.get_armor_pips().is_breathing())
	await wait_process_frames(1)
	assert_eq(card.get_buy_button().text, "Stop")
	assert_false(card.get_buy_button().disabled)
	assert_false(card.press_primary(), "the first press only arms it")
	assert_true(_player.upgrades.is_running(ARMOR))
	await wait_process_frames(1)
	assert_eq(card.get_buy_button().text, "Stop for sure")
	assert_true(card.press_primary())
	assert_false(_player.upgrades.is_running(ARMOR))
	assert_eq(_player.hold.amount(KYRITE), 1000.0, "the whole cost back")
	assert_eq(_player.hold.amount(VYREL), 1000.0)
	assert_false(_player.get_armor_pips().is_breathing())
	await wait_process_frames(1)
	assert_eq(card.get_buy_button().text, "Upgrade")


func test_card_shows_the_time_left() -> void:
	await _load_map()
	var station: UpgradeStation = await _open_station("Armor")
	var card := station.card_menu as UpgradeCard
	_player.upgrades.start(ARMOR, Time.get_unix_time_from_system() - 30.0)
	_player.upgrades.get_job(ARMOR).seconds = 3700.0
	await wait_process_frames(1)
	var effect := card.find_child("Effect", true, false) as Label
	assert_string_contains(effect.text, "MK2")
	assert_string_contains(card.get_time().text, "1:01:")
	assert_false(card.get_status().visible)
	var pips := card.find_child("Pips", true, false) as HBoxContainer
	var fill := pips.get_child(1).get_node(^"Fill") as ColorRect
	assert_true(fill.visible, "the pip of MK2 fills")
	assert_false((pips.get_child(2).get_node(^"Fill") as ColorRect).visible)


func test_done_levels_wait_for_the_end_of_a_run() -> void:
	await _load_map()
	_player.upgrades.start(ARMOR, 0.0)
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_process_frames(2)
	_ship.progress_clock.mission = _map.get_node("Mission") as Mission
	await wait_seconds(ProgressClock.TICK + 0.2)
	assert_true(_player.upgrades.is_running(ARMOR), "the mission is underway")
	_ship.progress_clock.tick(Time.get_unix_time_from_system())
	assert_eq(_player.upgrades.mk(ARMOR), 2, "a direct tick applies it")


func test_clock_lets_done_jobs_take_effect_with_a_chime() -> void:
	await _load_map()
	var health: float = _player.max_health()
	_player.upgrades.start(ARMOR, 0.0)
	_player.skills.start(DASH, 0.0)
	await wait_seconds(ProgressClock.TICK + 0.2)
	assert_eq(_player.upgrades.mk(ARMOR), 2)
	assert_eq(_player.skills.rank(DASH), 1)
	assert_gt(_player.max_health(), health, "the armor's health comes with it")
	assert_gt(Sfx.playing(ProgressClock.DONE_SOUND), 0)
	var armor := _ship.get_node("Rooms/Lower/Armor/UpgradeStation") as UpgradeStation
	assert_true(armor.sells(ARMOR))
	var skills := _ship.get_node("Rooms/Lower/Skills/SkillGraph") as SkillStation
	assert_true(skills.sells(DASH))
	assert_false(skills.sells(ARMOR))


func test_skill_graph_rings_a_skill_under_way() -> void:
	await _load_map()
	var graph := _ship.get_node("Rooms/Lower/Skills/SkillGraph") as SkillStation
	var ring := graph.get_part(DASH).get_node(^"Ring") as MeshInstance3D
	await wait_process_frames(1)
	assert_false(ring.visible)
	_player.skills.start(DASH, Time.get_unix_time_from_system())
	await wait_process_frames(1)
	assert_true(ring.visible)
	_player.skills.finish_all()
	await wait_process_frames(1)
	assert_false(ring.visible)


func test_debug_overlay_finishes_the_jobs() -> void:
	await _load_map()
	_player.upgrades.start(ARMOR, Time.get_unix_time_from_system())
	_player.skills.start(DASH, Time.get_unix_time_from_system())
	var overlay: CanvasLayer = get_tree().root.get_node("DebugOverlay") as CanvasLayer
	overlay.call(&"_finish_jobs")
	assert_eq(_player.upgrades.mk(ARMOR), 2)
	assert_eq(_player.skills.rank(DASH), 1)


func _load_map() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	_ship.ramp_duration = 0.25
	await wait_physics_frames(2)


func _open_station(room: String) -> UpgradeStation:
	var station := _ship.get_node("Rooms/Lower/%s/UpgradeStation" % room) as UpgradeStation
	station.open(_player)
	await wait_process_frames(2)
	return station
