extends GutTest
## The join quests of Dace, Wren and Fenna at their places at Waypost Ostra: what they talk about
## there before joining, their offers taking the place of their "coming aboard" topics
## (`Quest.replaces`), and a step handed in at them or their offer waiting on Ostra
## (`NpcProfile.station_in`, `StationWait`).

const TEST_MAP := preload("res://tests/support/map_fixture.gd")

var _map: Node3D
var _player: Player
var _ship: Ship
var _station: SpaceStation


func after_each() -> void:
	await wait_process_frames(1)


func test_dace_offers_his_quest_once_brannik_s_chain_is_done() -> void:
	await _dock_at_ostra()
	var dace: Npc = _people("Dace")
	assert_eq(_ids(dace), [&"gunsmith.about_stall", &"gunsmith.coming_aboard"] as Array[StringName])
	assert_false(dace.quests.has_news(_player))
	_ship.story.set_flag(&"quest.colony_arms")
	assert_eq(_ids(dace), [&"gunsmith.real_ore", &"gunsmith.about_stall"] as Array[StringName])
	assert_true(dace.quests.has_news(_player), "the diamond above him")


func test_wren_asks_once_she_has_been_talked_to() -> void:
	await _dock_at_ostra()
	var wren: Npc = _people("Wren")
	assert_eq(_ids(wren), [&"suit_tech.about_bench"] as Array[StringName])
	_ship.story.set_flag(&"suit_tech.about_bench")
	assert_eq(_ids(wren), [&"suit_tech.out_there", &"suit_tech.about_bench"] as Array[StringName])


func test_fenna_asks_once_the_other_three_are_aboard() -> void:
	await _dock_at_ostra()
	var fenna: Npc = _people("Fenna")
	assert_eq(_ids(fenna), [&"cook.about_booth", &"cook.cooking"] as Array[StringName])
	_ship.story.set_flag(&"crew.gunsmith.joined")
	_ship.story.set_flag(&"crew.suit_tech.joined")
	assert_has(_ids(fenna), &"cook.cooking", "Hollis isn't aboard yet")
	_ship.story.set_flag(&"crew.miner_mechanic.joined")
	assert_eq(_ids(fenna), [&"cook.rooks_leftovers", &"cook.about_booth"] as Array[StringName])
	assert_true(fenna.quests.has_news(_player))


func test_they_wait_on_ostra_until_they_join() -> void:
	var story := Story.new()
	for id: StringName in [&"gunsmith", &"suit_tech", &"cook"]:
		var profile: NpcProfile = NpcProfile.find(id)
		assert_eq(profile.station_in(story), &"ostra", String(id))
		story.set_flag(profile.join_flag)
		assert_eq(profile.station_in(story), &"", String(id) + " aboard")
	var hollis: NpcProfile = NpcProfile.find(&"miner_mechanic")
	assert_eq(hollis.station_in(Story.new()), &"", "Hollis waits out there")
	assert_eq(NpcProfile.find(&"depot_master").station_in(story), &"ostra")


func test_fenna_s_offer_waits_on_ostra_until_it_is_heard() -> void:
	var director := StoryDirector.new()
	director.catalog = BeatCatalog.new()
	director.quests.story = director.story
	assert_true(StationWait.find_all(director).is_empty(), "a new game")
	for joined: StringName in [&"gunsmith", &"suit_tech", &"miner_mechanic"]:
		director.story.set_flag(NpcProfile.find(joined).join_flag)
	var waits: Array[StationWait] = StationWait.find_all(director)
	assert_eq(waits.size(), 1)
	if waits.size() == 1:
		assert_eq(waits[0].npc, &"cook")
		assert_eq(waits[0].station, &"ostra")
		assert_eq(waits[0].quest.id, &"rooks_leftovers")
	director.story.set_flag(&"cook.rooks_leftovers")
	assert_true(StationWait.find_all(director).is_empty(), "heard")


func _ids(npc: Npc) -> Array[StringName]:
	var ids: Array[StringName] = []
	for listed: Topic in npc.get_choices(_player):
		ids.append(listed.id)
	return ids


## The test map docked at Ostra with the four who join later not aboard yet.
func _dock_at_ostra() -> void:
	SaveGame.directory = ""
	_map = TEST_MAP.instantiate(false) as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	var voyage := _map.get_node("Voyage") as Voyage
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)
	var ostra: CelestialBody = voyage.settings.system.body_by_id(&"ostra")
	voyage.select(voyage.offer_for_station(ostra))
	voyage.skip_flight()
	await wait_physics_frames(3)
	_station = voyage.location as SpaceStation


func _people(who: String) -> Npc:
	return _station.get_node("People/" + who) as Npc
