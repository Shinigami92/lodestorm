extends GutTest
## What the active quest steps put into a visit to a region (`QuestVisit`): their quest sites,
## quest nests and hunts (a brood nest, a lair), in the location too, and what's done there
## counting once someone is back aboard.

const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")
const CAMP: PackedScene = preload("res://game/locations/parts/expedition_camp.tscn")
const DEN: PackedScene = preload("res://game/locations/parts/den.tscn")
const HIVE_HOLLOW: PackedScene = preload("res://game/locations/parts/hive_hollow.tscn")
const BROOD: PackedScene = preload("res://game/aliens/nest/brood_clutch.tscn")
const HIVE: AlienHive = preload("res://game/aliens/hive/hive.tres")
const SPITTER: AlienStrain = preload("res://game/aliens/strains/spitter/spitter.tres")
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


## A hunt in `REGION`: five spitters from an egg clutch in a den, or the Ravager in its lair.
static func make_hunt(apex: bool = false) -> Quest:
	var hunt := HuntGoal.new()
	hunt.region = REGION
	hunt.site_part = PartPlacement.new()
	hunt.site_part.scene = HIVE_HOLLOW if apex else DEN
	hunt.strain = HIVE.apex if apex else SPITTER
	hunt.amount = 5
	if not apex:
		hunt.nest_scene = BROOD
	var step := QuestStep.new()
	step.id = &"hunt"
	step.goals = [hunt]
	var quest := Quest.new()
	quest.id = &"the_hunt"
	quest.giver = &"quartermaster"
	quest.steps = [step]
	return quest


func _accept_hunt(apex: bool = false) -> Quest:
	var quest: Quest = make_hunt(apex)
	_log.catalog.quests = [quest]
	_log.accept(quest, [])
	return quest


func test_a_hunt_needs_its_kills_and_then_the_brood_nest() -> void:
	var quest: Quest = _accept_hunt()
	var visit := QuestVisit.new(_log, REGION)
	var entry: QuestVisit.Entry = visit.entries[0]
	assert_eq(entry.hunted, SPITTER)
	assert_eq(entry.brood, BROOD)
	assert_eq(visit.kills_left(entry), 5)
	for i: int in 7:
		visit.count_kill(entry)
	visit.commit()
	assert_eq(_log.goal_progress(quest, 0), 5.0, "the kills, not the nest")
	var next := QuestVisit.new(_log, REGION)
	assert_eq(next.entries.size(), 1, "the brood nest comes again")
	assert_eq(next.kills_left(next.entries[0]), 0, "hatching no more for the hunt")
	next.count_brood(next.entries[0])
	next.commit()
	assert_eq(_log.goal_progress(quest, 0), 6.0, "done")


func test_the_brood_nest_counts_once_the_kills_are_done() -> void:
	var quest: Quest = _accept_hunt()
	var visit := QuestVisit.new(_log, REGION)
	var entry: QuestVisit.Entry = visit.entries[0]
	visit.count_brood(entry)
	for i: int in 3:
		visit.count_kill(entry)
	visit.commit()
	assert_eq(_log.goal_progress(quest, 0), 3.0, "the nest waits for the kills")
	for i: int in 2:
		visit.count_kill(entry)
	visit.commit()
	assert_eq(_log.goal_progress(quest, 0), 6.0, "back aboard with every kill: the nest too")


func test_a_lost_run_forgets_the_brood_nest() -> void:
	var quest: Quest = _accept_hunt()
	var visit := QuestVisit.new(_log, REGION)
	var entry: QuestVisit.Entry = visit.entries[0]
	for i: int in 5:
		visit.count_kill(entry)
	visit.count_brood(entry)
	visit.drop()
	visit.commit()
	assert_eq(_log.goal_progress(quest, 0), 0.0)


func test_the_cards_count_only_the_kills() -> void:
	var hunt := make_hunt().steps[0].goals[0] as HuntGoal
	assert_eq(hunt.target(), 6.0)
	assert_eq(hunt.counted(), 5.0)
	var lair := make_hunt(true).steps[0].goals[0] as HuntGoal
	assert_eq(lair.target(), 1.0)
	assert_eq(lair.counted(), 1.0)


## The location puts the brood nest at the den's anchor: it hatches only spitters, as many as the
## hunt needs, once a player comes close; their kills and the nest count.
func test_the_location_places_the_brood_nest() -> void:
	var quest: Quest = _accept_hunt()
	var location: GeneratedLocation = _location()
	var nest := location.get_node_or_null(^"AlienNests/BroodNest") as AlienNest
	assert_not_null(nest, "a brood nest")
	var den: LocationParts.Placed = location.parts.placed_for(location.quest_visit.entries[0].site)
	assert_not_null(den, "the den placed")
	if not nest or not den:
		return
	assert_eq(nest.position, den.markers(PartMarker.Kind.QUEST_ANCHOR)[0], "at its anchor")
	assert_eq(nest.kind, AlienNest.Kind.BROOD)
	assert_eq(nest.brood, SPITTER)
	assert_eq(nest.brood_left, 5)
	assert_false(nest.is_awake(), "asleep until a player comes close")
	nest.hatch(Alien.Role.HUNTER, SPITTER).take_damage(1.0e6)
	nest.body.take_damage(1.0e6)
	location.quest_visit.commit()
	assert_eq(_log.goal_progress(quest, 0), 1.0, "a kill; the nest waits for the rest")


## A Ravager hunt: it sleeps at the hollow's anchor (the location's own doesn't roam), and its
## death counts.
func test_the_location_places_the_lair() -> void:
	var quest: Quest = _accept_hunt(true)
	var location: GeneratedLocation = _location()
	var lair := location.get_node_or_null(^"Lair") as ApexLair
	assert_not_null(lair, "a lair")
	assert_null(location.get_node_or_null(^"Apex"), "no other Ravager")
	if not lair:
		return
	assert_eq(lair.apex.strain, HIVE.apex)
	assert_true(lair.apex.status.asleep, "asleep")
	lair.apex.take_damage(1.0e9)
	location.quest_visit.commit()
	assert_eq(_log.goal_progress(quest, 0), 1.0)


func _location() -> GeneratedLocation:
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = 5
	location.biome = DUST
	location.area_count = 6
	location.alien_tier = 3
	location.quest_visit = QuestVisit.new(_log, REGION)
	add_child_autofree(location)
	return location
