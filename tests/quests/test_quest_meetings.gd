extends GutTest
## A step handed in at someone out in a region (`QuestStep.meets_at`, e.g. Hollis at his camp):
## they wait at their part in every visit while it's active, the next step's goals in the region
## are there already, it's handed in during the run (`QuestVisit.hand_in`) and a lost run takes it
## back; in the location they stand at the part's person marker and are talked to there.

const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")
const CAMP: PackedScene = preload("res://game/locations/parts/hollis_camp.tscn")
const DIG_SITE: PackedScene = preload("res://game/locations/parts/hollis_dig_site.tscn")
const OUTPOST: PackedScene = preload("res://game/locations/parts/outpost.tscn")
const REGION: StringName = &"redscar"
const HOLLIS: StringName = &"miner_mechanic"

var _log: QuestLog
var _quest: Quest


func before_each() -> void:
	_quest = make_quest()
	_log = QuestLog.new()
	_log.catalog = QuestCatalog.new()
	_log.catalog.quests = [_quest]


## Find Hollis' camp (handed in at him there), then clear the nest at his dig site and bring a part
## from a crate (an outpost brings one; handed in there too: he joins).
static func make_quest() -> Quest:
	var camp := PartPlacement.new()
	camp.scene = CAMP
	var reach := ReachGoal.new()
	reach.region = REGION
	reach.site_part = camp
	reach.place = "Hollis' camp"
	var find := QuestStep.new()
	find.id = &"find"
	find.goals = [reach]
	find.hand_in_to = HOLLIS
	find.meets_in = REGION
	find.meets_at = camp
	var nest := ClearNestsGoal.new()
	nest.region = REGION
	nest.amount = 1
	nest.site_part = PartPlacement.new()
	nest.site_part.scene = DIG_SITE
	var part := RecoverFragmentsGoal.new()
	part.region = REGION
	part.amount = 1
	part.site_part = PartPlacement.new()
	part.site_part.scene = OUTPOST
	var free := QuestStep.new()
	free.id = &"free"
	free.goals = [nest, part]
	free.hand_in_to = HOLLIS
	free.meets_in = REGION
	free.meets_at = camp
	free.joins = HOLLIS
	var quest := Quest.new()
	quest.id = &"overdue_test"
	quest.giver = &"depot_master"
	quest.steps = [find, free]
	return quest


func test_they_wait_at_their_part_while_the_step_is_active() -> void:
	assert_true(QuestVisit.new(_log, REGION).meetings.is_empty(), "not before it's accepted")
	_log.accept(_quest, [])
	var visit := QuestVisit.new(_log, REGION)
	assert_eq(visit.meetings.size(), 1)
	assert_eq(visit.meeting_for(_quest), visit.meetings[0])
	assert_eq(visit.sites().size(), 3, "the camp (shared), the dig site and the outpost")
	assert_eq(visit.meetings[0].site, visit.entries[0].site)
	assert_true(QuestVisit.regions(_log).has(REGION))
	assert_true(QuestVisit.new(_log, &"mire").meetings.is_empty(), "only in its region")


func test_the_next_steps_goals_are_there_already() -> void:
	_log.accept(_quest, [])
	_log.tracked = _quest.id
	var visit := QuestVisit.new(_log, REGION)
	assert_eq(visit.entries.size(), 3, "the camp, the nest at his dig site and his part")
	assert_true(visit.entries[2].upcoming)
	assert_eq(visit.fragment_entries().size(), 1, "his part in a crate already")
	var nest: QuestVisit.Entry = visit.entries[1]
	assert_true(nest.upcoming)
	assert_eq(nest.site.scene, DIG_SITE, "at his dig site")
	assert_true(visit.nest_entries().is_empty(), "not spread over the region")
	assert_false(visit.is_tracked(nest), "no mark before its step starts")
	visit.count(nest)
	visit.commit()
	assert_eq(_log.goal_progress(_quest, 0), 0.0, "counts only once its step starts")


func test_handed_in_out_there_during_the_run() -> void:
	_log.accept(_quest, [])
	var visit := QuestVisit.new(_log, REGION)
	var payer: Player = autofree(Player.new())
	assert_false(visit.hand_in(_quest, payer, []), "the camp isn't found yet")
	visit.count(visit.entries[1])
	visit.count(visit.entries[0])
	assert_true(visit.is_ready(_quest))
	watch_signals(visit)
	assert_true(visit.hand_in(_quest, payer, []))
	assert_eq(_log.current_step(_quest), _quest.steps[1], "the next step at once")
	assert_signal_emitted(visit, "extended")
	assert_eq(visit.entries.size(), 3, "nothing new: the next step's goals were there")
	assert_false(visit.entries[1].upcoming, "the nest counts now")
	assert_false(visit.entries[2].upcoming, "his part too")
	assert_eq(visit.meetings.size(), 2)
	assert_eq(visit.meeting_for(_quest), visit.meetings[1])
	assert_eq(visit.progress(_quest, 0), 1.0, "the nest destroyed before")
	visit.count(visit.entries[2])
	assert_true(visit.hand_in(_quest, payer, []))
	assert_true(_log.is_done(_quest))
	assert_true(_log.story.is_set(&"crew.miner_mechanic.joined"), "he joins")


func test_a_lost_run_takes_it_back() -> void:
	_log.accept(_quest, [])
	var visit := QuestVisit.new(_log, REGION)
	var payer: Player = autofree(Player.new())
	visit.count(visit.entries[0])
	visit.hand_in(_quest, payer, [])
	visit.count(visit.entries[1])
	visit.count(visit.entries[2])
	visit.hand_in(_quest, payer, [])
	visit.drop()
	assert_eq(_log.current_step(_quest), _quest.steps[0], "back at the first step")
	assert_eq(_log.goal_progress(_quest, 0), 0.0, "his camp not found")
	assert_false(_log.story.is_set(&"crew.miner_mechanic.joined"), "he hasn't joined")
	assert_false(_log.story.is_set(_quest.flag()))


func test_someone_aboard_keeps_it() -> void:
	_log.accept(_quest, [])
	var visit := QuestVisit.new(_log, REGION)
	var payer: Player = autofree(Player.new())
	visit.count(visit.entries[0])
	visit.hand_in(_quest, payer, [])
	visit.commit()
	visit.drop()
	assert_eq(_log.current_step(_quest), _quest.steps[1], "still handed in")
	var next := QuestVisit.new(_log, REGION)
	assert_eq(next.meeting_for(_quest), next.meetings[0], "he waits for the next step")
	assert_eq(next.entries.size(), 2, "the nest at his dig site and his part")


## The location places the camp, Hollis at its person marker (talked to about what's out here),
## the nest at his dig site and his part in a crate.
func test_the_location_places_them() -> void:
	_log.accept(_quest, [])
	_log.tracked = _quest.id
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = 5
	location.biome = DUST
	location.area_count = 10
	location.quest_visit = QuestVisit.new(_log, REGION)
	# Built outside the tree first, like a prepared location the holo table previews.
	location.build()
	var early := location.quests.person(HOLLIS).get_node(^"HandInMark") as HandInMark
	assert_false(early.is_lit(), "asked outside the tree")
	add_child_autofree(location)
	var visit: QuestVisit = location.quest_visit
	var hollis: Npc = location.quests.person(HOLLIS)
	var camp: LocationParts.Placed = location.parts.placed_for(visit.meetings[0].site)
	assert_not_null(hollis, "he waits there")
	assert_not_null(camp, "the camp placed")
	if not hollis or not camp:
		return
	assert_eq(hollis.position, camp.transform() * _spot(camp), "at its person marker")
	assert_true(hollis.waits_to_join)
	assert_true(hollis.get_quests() is VisitQuests, "the quests as they are out here")
	assert_has(hollis.get_choices(), _quest.steps[0].hand_in, "the hand-in")
	assert_true(hollis.use_point.enabled, "talked to there")
	var mark := hollis.get_node(^"HandInMark") as HandInMark
	assert_false(mark.is_lit(), "the camp isn't found yet")
	var nests: Array[Node] = location.get_node(^"AlienNests").get_children().filter(
		func(nest: Node) -> bool: return nest.name.begins_with("QuestNest")
	)
	assert_eq(nests.size(), 1, "the nest at his dig site")
	var dig: LocationParts.Placed = location.parts.placed_for(visit.entries[1].site)
	if dig and not nests.is_empty():
		var spot: Vector3 = dig.markers(PartMarker.Kind.QUEST_NEST)[0]
		assert_eq((nests[0] as Node3D).position, spot, "at its quest nest marker")
	var aliens_kept_off := hollis.get_node(^"HandRepeller") as AlienRepeller
	assert_not_null(aliens_kept_off, "his hand repeller")
	(location.get_node(^"QuestSite") as QuestSite).reached.emit(null)
	assert_true(mark.is_lit(), "the camp found: back to him")
	var filled: Array[Crate] = []
	for crate: Crate in location.find_children("*", "Crate", true, false):
		if crate.content is BlueprintFragment:
			filled.append(crate)
	assert_eq(filled.size(), 1, "his part in a crate")
	var payer: Player = autofree(Player.new())
	assert_true(hollis.get_quests().hand_in(_quest, payer, []), "handed in out there")
	assert_eq(_log.current_step(_quest), _quest.steps[1])


## Where `camp`'s person marker is, in the part.
func _spot(camp: LocationParts.Placed) -> Vector3:
	for i: int in camp.info.marker_kinds.size():
		if camp.info.marker_kinds[i] == PartMarker.Kind.PERSON:
			return camp.info.marker_spots[i].origin
	return Vector3.INF
