extends GutTest
## Carried quest items (`RecoverFragmentsGoal`, `RecoverItemGoal`): fragments in a visit's crates,
## an item at its site, carried on the back (`QuestPack`), counting once their carrier is aboard and
## lost when they die.

const LOCATION: PackedScene = preload("res://game/locations/generated_location.tscn")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const DUST: LocationBiome = preload("res://game/locations/biomes/dust.tres")
const CAMP: PackedScene = preload("res://game/locations/parts/expedition_camp.tscn")
const WRECK: PackedScene = preload("res://game/locations/parts/wreck.tscn")
const CASE: PackedScene = preload("res://game/quests/items/sealed_case.tscn")
const REGION: StringName = &"redscar"

var _log: QuestLog
var _quest: Quest


func before_each() -> void:
	_quest = make_quest()
	_log = QuestLog.new()
	_log.catalog = QuestCatalog.new()
	_log.catalog.quests = [_quest]
	_log.accept(_quest, [])


## A quest in `REGION`: recover three fragments (a wreck in every visit) and the survey team's case
## at the expedition's camp.
static func make_quest() -> Quest:
	var fragments := RecoverFragmentsGoal.new()
	fragments.region = REGION
	fragments.amount = 3
	fragments.site_part = PartPlacement.new()
	fragments.site_part.scene = WRECK
	var item := RecoverItemGoal.new()
	item.region = REGION
	item.site_part = PartPlacement.new()
	item.site_part.scene = CAMP
	item.item = "the survey team's case"
	item.item_scene = CASE
	var step := QuestStep.new()
	step.id = &"recover"
	step.goals = [fragments, item]
	var quest := Quest.new()
	quest.id = &"lost_survey"
	quest.giver = &"quartermaster"
	quest.steps = [step]
	return quest


func test_the_visit_wants_the_fragments_still_to_find() -> void:
	var visit := QuestVisit.new(_log, REGION)
	assert_eq(visit.fragment_entries().size(), 3)
	assert_eq(visit.sites().size(), 2, "the wreck and the camp")
	visit.count_carried([visit.entries[0]])
	visit.commit()
	var next := QuestVisit.new(_log, REGION)
	assert_eq(next.fragment_entries().size(), 2)
	assert_ne(next.key(), visit.key())


## Carried items count only once brought aboard; a fragment of another visit counts nothing.
func test_carried_items_count_once_aboard() -> void:
	var visit := QuestVisit.new(_log, REGION)
	var pack := QuestPack.new()
	add_child_autofree(pack)
	pack.add(visit.entries[0])
	pack.add(visit.entries[0])
	pack.add(visit.entries[1])
	assert_eq(pack.fragment_count(), 2)
	assert_eq(pack.item_count(), 1)
	visit.commit()
	assert_eq(_log.goal_progress(_quest, 0), 0.0, "not before its carrier is aboard")
	visit.count_carried(pack.take_all())
	visit.commit()
	assert_eq(_log.goal_progress(_quest, 0), 2.0)
	assert_eq(_log.goal_progress(_quest, 1), 1.0)
	assert_eq(pack.carried.size(), 0)
	var other := QuestVisit.new(_log, REGION)
	visit.count_carried(other.entries)
	visit.commit()
	assert_eq(_log.goal_progress(_quest, 0), 2.0, "only this visit's")


## The location puts the fragments into its crates (the wreck brings one) and the case at the
## camp's anchor; opening a fragment's crate and picking the case up put them on the back.
func test_the_location_places_the_fragments_and_the_item() -> void:
	var location := LOCATION.instantiate() as GeneratedLocation
	location.world_seed = 5
	location.biome = DUST
	location.area_count = 6
	location.quest_visit = QuestVisit.new(_log, REGION)
	add_child_autofree(location)
	var crates: Array[Node] = location.find_children("*", "Crate", true, false)
	var fragments: Array[BlueprintFragment] = []
	for crate: Crate in crates:
		if crate.content is BlueprintFragment:
			fragments.append(crate.content as BlueprintFragment)
	assert_gt(crates.size(), 0, "the wreck's crate at least")
	assert_eq(fragments.size(), mini(crates.size(), 3), "one per crate")
	assert_null(location.get_node_or_null(^"QuestSite"), "no site to reach")
	var item := location.get_node_or_null(^"QuestItem") as QuestItem
	assert_not_null(item, "the case")
	var camp: LocationParts.Placed = location.parts.placed_for(location.quest_visit.entries[1].site)
	assert_not_null(camp, "the camp placed")
	if fragments.is_empty() or not item or not camp:
		return
	assert_eq(item.position, camp.markers(PartMarker.Kind.QUEST_ANCHOR)[0], "at its anchor")
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	fragments[0].open(player)
	item.use(player)
	assert_eq(player.quest_pack.fragment_count(), 1)
	assert_eq(player.quest_pack.item_count(), 1)
	assert_true(item.is_queued_for_deletion(), "picked up")
	location.quest_visit.count_carried(player.quest_pack.take_all())
	location.quest_visit.commit()
	assert_eq(_log.goal_progress(_quest, 0), 1.0)
	assert_eq(_log.goal_progress(_quest, 1), 1.0)


## Dying loses what's carried; the next visit wants it again.
func test_lost_when_the_carrier_dies() -> void:
	var visit := QuestVisit.new(_log, REGION)
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.quest_pack.add(visit.entries[0])
	player.quest_pack.add(visit.entries[1])
	assert_eq(player.get_node(^"QuestPack").get_child_count(), 2, "on the back")
	player.take_damage(player.settings.max_health + 50.0)
	assert_true(player.dead)
	assert_eq(player.quest_pack.carried.size(), 0)
	visit.count_carried(player.quest_pack.take_all())
	visit.commit()
	assert_eq(QuestVisit.new(_log, REGION).fragment_entries().size(), 3)
	assert_eq(QuestVisit.new(_log, REGION).sites().size(), 2, "the case waits at the camp")
