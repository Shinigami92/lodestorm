extends GutTest
## Crew members who join later (`NpcProfile.join_flag`): not aboard at a new game's start, a
## stand-in topic covering their post, lines naming them only once they're aboard, heat shield MK2
## waiting for the whole crew and a quest step bringing them aboard.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const TALKS: TalkCatalog = preload("res://game/talks/talks.tres")
const QUEST_LOG_TEST := preload("res://tests/quests/test_quest_log.gd")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")

## The four aboard from the start and the four joining in act 1, by their node in the ship.
const FROM_THE_START: Array[String] = [
	"Rooms/Lower/Armory/Quartermaster",
	"Rooms/Upper/Bridge/Pilot",
	"Rooms/Lower/EngineRoom/Engineer",
	"Rooms/Lower/MedicalBay/Medic",
]
const JOINING: Array[String] = [
	"Rooms/Lower/Weapons/Gunsmith",
	"Rooms/Lower/Armor/SuitTech",
	"Rooms/Lower/Miners/MinerMechanic",
	"Rooms/Upper/MessHall/Cook",
]

var _map: Node3D
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate(false) as Node3D
	add_child_autofree(_map)
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func after_each() -> void:
	await wait_process_frames(1)


func test_four_aboard_at_the_start_and_four_join_later() -> void:
	for path: String in FROM_THE_START:
		var npc := _ship.get_node(path) as Npc
		assert_true(npc.is_present(), path)
		assert_true(npc.visible and npc.use_point.enabled, path)
	for path: String in JOINING:
		var npc := _ship.get_node(path) as Npc
		assert_false(npc.is_present(), path)
		assert_false(npc.visible or npc.use_point.enabled, path)
		assert_eq(npc.process_mode, Node.PROCESS_MODE_DISABLED, path)
	assert_eq(_ship.reactions.crew().size(), FROM_THE_START.size(), "only those aboard call in")
	assert_eq(NpcProfile.crew().size(), FROM_THE_START.size() + JOINING.size())


func test_joining_brings_them_to_their_post() -> void:
	var dace := _ship.get_node("Rooms/Lower/Weapons/Gunsmith") as Npc
	_ship.story.set_flag(dace.profile.join_flag)
	assert_true(dace.visible and dace.use_point.enabled)
	assert_eq(dace.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_has(_ship.reactions.crew(), dace)


func test_a_stand_in_topic_until_they_join() -> void:
	var brannik := _ship.get_node("Rooms/Lower/Armory/Quartermaster") as Npc
	_ship.story.set_flag(&"quartermaster.greeting")
	assert_true(_has_topic(brannik, &"quartermaster.weapons_room"), "explains the weapons room")
	_ship.story.set_flag(&"crew.gunsmith.joined")
	assert_false(_has_topic(brannik, &"quartermaster.weapons_room"), "Dace explains it himself")


func test_the_tour_names_them_once_aboard() -> void:
	var tour: Tour = NpcProfile.find(&"quartermaster").tour
	var weapons: TourStop = null
	for stop: TourStop in tour.stops:
		if stop.id == &"Weapons":
			weapons = stop
	assert_eq(weapons.lines_for(_ship.story), weapons.empty_lines)
	_ship.story.set_flag(&"crew.gunsmith.joined")
	assert_eq(weapons.lines_for(_ship.story), weapons.lines)


func test_a_reaction_naming_them_waits_for_them() -> void:
	var brannik: NpcProfile = NpcProfile.find(&"quartermaster")
	var before: Array[String] = brannik.reaction_lines(&"big_haul", &"", false, _ship.story)
	assert_false(before.any(func(line: String) -> bool: return "Dace" in line))
	NpcProfile.join_whole_crew(_ship.story)
	var after: Array[String] = brannik.reaction_lines(&"big_haul", &"", false, _ship.story)
	assert_true(after.any(func(line: String) -> bool: return "Dace" in line))
	assert_eq(after.size(), before.size() + 1, "the same lines and one more")


func test_heat_shield_mk2_waits_for_the_whole_crew() -> void:
	var core := _ship.get_node("Rooms/Lower/EngineRoom/DriveCore") as HeatShieldStation
	var player := _map.get_node("Player") as Player
	var use: Interactable = core.use_point
	player.global_position = use.to_global(
		Vector3(0.0, 0.0, use.footprint.y * 0.5 + use.interact_range - 0.3)
	)
	player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(player.interact(), use)
	await wait_process_frames(1)
	assert_true(core.waits_for_crew(2))
	assert_false(core.set_project(2), "not with someone missing")
	var card := core.card_menu as HeatShieldCard
	assert_true(card.get_project_button().disabled)
	NpcProfile.join_whole_crew(_ship.story)
	assert_false(core.waits_for_crew(2))
	assert_true(core.set_project(2))
	core.close()


func test_a_quest_step_brings_them_aboard() -> void:
	var quest: Quest = QUEST_LOG_TEST.make_quest(&"real_ore", &"gunsmith")
	quest.steps = [quest.steps[0]]
	quest.steps[0].joins = &"gunsmith"
	var quests := QuestLog.new()
	quests.catalog = QuestCatalog.new()
	quests.catalog.quests = [quest]
	quests.accept(quest, [])
	quests.take_from({KYRITE: 300.0})
	var payer: Player = autofree(Player.new())
	assert_true(quests.hand_in(quest, payer, []))
	assert_true(quests.story.is_set(&"crew.gunsmith.joined"))


## Every line of the crew, and of their overheard talks, that names a crew member who joins later
## waits for them: a topic or a reaction requires their join flag, a tour stop is their room (its
## `empty_lines` without their name); their own lines don't count.
func test_lines_name_someone_only_once_they_are_aboard() -> void:
	var joining: Array[NpcProfile] = NpcProfile.crew().filter(
		func(profile: NpcProfile) -> bool: return not profile.join_flag.is_empty()
	)
	assert_eq(joining.size(), JOINING.size())
	for speaker: NpcProfile in NpcProfile.crew():
		for named: NpcProfile in joining:
			if named != speaker:
				_check_profile(speaker, named)
	for talk: OverheardTalk in TALKS.talks:
		for named: NpcProfile in joining:
			var names: bool = talk.lines.any(
				func(line: TalkLine) -> bool: return named.display_name in line.text
			)
			if names or named.id in talk.speakers():
				assert_has(talk.requires, named.join_flag, "%s: %s" % [talk.id, named.id])


func _check_profile(speaker: NpcProfile, named: NpcProfile) -> void:
	var who: String = "%s naming %s" % [speaker.id, named.display_name]
	var topics: Array[Topic] = [speaker.dialogue.greeting]
	topics.append_array(speaker.dialogue.topics)
	if speaker.tour:
		var tour: Tour = speaker.tour
		topics.append_array([tour.offer, tour.invite, tour.resume, tour.abort])
		for stop: TourStop in tour.stops:
			if _names(stop.lines, named):
				assert_eq(stop.crew_member, named.id, "%s: tour stop %s" % [who, stop.id])
			assert_false(_names(stop.empty_lines, named), "%s: tour stop %s" % [who, stop.id])
	for topic: Topic in topics:
		if topic and _names(_joined([topic.lines, topic.guest_lines, topic.away_lines]), named):
			assert_has(topic.requires, named.join_flag, "%s: %s" % [who, topic.id])
	for reaction: CrewReaction in speaker.reactions:
		if _names(reaction.lines, named):
			assert_has(reaction.requires, named.join_flag, "%s: %s" % [who, reaction.event])
	assert_false(_names(_joined([speaker.remarks, speaker.calls]), named), who)


func _names(lines: Array[String], named: NpcProfile) -> bool:
	return lines.any(func(line: String) -> bool: return named.display_name in line)


func _joined(lists: Array[Array]) -> Array[String]:
	var all: Array[String] = []
	for list: Array in lists:
		all.append_array(list)
	return all


func _has_topic(npc: Npc, id: StringName) -> bool:
	return npc.get_choices().any(func(topic: Topic) -> bool: return topic.id == id)
