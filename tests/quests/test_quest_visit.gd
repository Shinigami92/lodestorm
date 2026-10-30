extends GutTest
## What the active quest steps put into a visit to a region (`QuestVisit`): their quest sites and
## quest nests, in the location too, and what's done there counting once someone is back aboard.

const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")
const CAMP: PackedScene = preload("res://game/locations/parts/expedition_camp.tscn")
const REGION: StringName = &"redscar"

var _log: QuestLog
var _quest: Quest


func before_each() -> void:
	_quest = make_quest()
	_log = QuestLog.new()
	_log.catalog = QuestCatalog.new()
	_log.catalog.quests = [_quest]


## A quest out in `REGION`: find the camp and clear two nests, then clear one more.
static func make_quest() -> Quest:
	var reach := ReachGoal.new()
	reach.region = REGION
	reach.site_part = PartPlacement.new()
	reach.site_part.scene = CAMP
	reach.place = "the expedition's camp"
	var nests := ClearNestsGoal.new()
	nests.region = REGION
	nests.amount = 2
	var first := QuestStep.new()
	first.id = &"camp"
	first.goals = [reach, nests]
	var more := ClearNestsGoal.new()
	more.region = REGION
	more.amount = 1
	var second := QuestStep.new()
	second.id = &"more"
	second.goals = [more]
	var quest := Quest.new()
	quest.id = &"camp_search"
	quest.giver = &"quartermaster"
	quest.steps = [first, second]
	return quest


func test_nothing_before_the_quest_is_accepted() -> void:
	assert_eq(QuestVisit.new(_log, REGION).entries.size(), 0)


func test_the_active_steps_goals_in_their_region() -> void:
	_log.accept(_quest, [])
	var visit := QuestVisit.new(_log, REGION)
	assert_eq(visit.entries.size(), 2)
	assert_eq(visit.sites().size(), 1)
	assert_eq(visit.sites()[0].scene, CAMP)
	var site: PartPlacement = (_quest.steps[0].goals[0] as RegionGoal).site()
	assert_ne(visit.sites()[0], site, "a part of its own")
	assert_eq(visit.nest_entries().size(), 2)
	assert_eq(QuestVisit.new(_log, &"hollow_mire").entries.size(), 0, "only its region")


func test_counts_once_committed() -> void:
	_log.accept(_quest, [])
	var visit := QuestVisit.new(_log, REGION)
	visit.count(visit.entries[0])
	visit.count(visit.entries[1])
	assert_eq(_log.goal_progress(_quest, 0), 0.0, "not before someone is aboard")
	visit.commit()
	assert_eq(_log.goal_progress(_quest, 0), 1.0)
	assert_eq(_log.goal_progress(_quest, 1), 1.0)
	visit.commit()
	assert_eq(_log.goal_progress(_quest, 1), 1.0, "counted once")
	var next := QuestVisit.new(_log, REGION)
	assert_eq(next.entries.size(), 1, "the site is found")
	assert_eq(next.nest_entries().size(), 1, "only the nests left")


func test_never_more_than_the_goal_needs() -> void:
	_log.accept(_quest, [])
	var visit := QuestVisit.new(_log, REGION)
	for i: int in 3:
		visit.count(visit.entries[1])
	visit.commit()
	assert_eq(_log.goal_progress(_quest, 1), 2.0)


func test_a_lost_run_counts_nothing() -> void:
	_log.accept(_quest, [])
	var visit := QuestVisit.new(_log, REGION)
	visit.count(visit.entries[0])
	visit.drop()
	visit.commit()
	assert_eq(_log.goal_progress(_quest, 0), 0.0)


func test_a_step_handed_in_takes_nothing_more() -> void:
	_log.accept(_quest, [])
	var visit := QuestVisit.new(_log, REGION)
	visit.count(visit.entries[0])
	visit.count(visit.entries[1], 2.0)
	visit.commit()
	var payer: Player = autofree(Player.new())
	assert_true(_log.hand_in(_quest, payer, []))
	visit.count(visit.entries[1])
	visit.commit()
	assert_eq(_log.goal_progress(_quest, 0), 0.0, "the next step's goal")


func test_its_key_follows_what_it_places() -> void:
	_log.accept(_quest, [])
	var before: String = QuestVisit.new(_log, REGION).key()
	assert_eq(QuestVisit.new(_log, REGION).key(), before)
	var visit := QuestVisit.new(_log, REGION)
	visit.count(visit.entries[1])
	visit.commit()
	assert_ne(QuestVisit.new(_log, REGION).key(), before)


## The location places the camp with a quest site at its anchor and the quest nests (their own
## kind); reaching the site and destroying a quest nest count.
func test_the_location_places_the_site_and_the_nests() -> void:
	_log.accept(_quest, [])
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = 5
	location.biome = DUST
	location.area_count = 6
	location.quest_visit = QuestVisit.new(_log, REGION)
	add_child_autofree(location)
	var site := location.get_node_or_null(^"QuestSite") as QuestSite
	assert_not_null(site, "a quest site")
	var camp: LocationParts.Placed = location.parts.placed_for(location.quest_visit.entries[0].site)
	assert_not_null(camp, "the camp placed")
	if not site or not camp:
		return
	assert_eq(site.position, camp.markers(PartMarker.Kind.QUEST_ANCHOR)[0], "at its anchor")
	var quest_nests: Array[AlienNest] = []
	for nest: AlienNest in location.get_node(^"AlienNests").get_children():
		if nest.kind == AlienNest.Kind.QUEST:
			quest_nests.append(nest)
	assert_eq(quest_nests.size(), 2)
	site.reached.emit(null)
	quest_nests[0].body.take_damage(1.0e6)
	location.quest_visit.commit()
	assert_eq(_log.goal_progress(_quest, 0), 1.0, "the site reached")
	assert_eq(_log.goal_progress(_quest, 1), 1.0, "a quest nest destroyed")
