extends GutTest
## Who says which line (`VoiceLines.lines_by_speaker`, what `tools/voice.sh` voices): a profile's
## own lines (`NpcProfile.spoken_lines`), and lines from other files said by the NPC they name.


## Says a line of the depot master's from another file, like a quest's hand-in.
class HandIn:
	extends Resource

	func spoken_lines() -> Dictionary[StringName, PackedStringArray]:
		var said: Dictionary[StringName, PackedStringArray] = {
			&"depot_master": PackedStringArray(["That's all of it. Thanks."])
		}
		return said


func test_a_profile_says_every_line_it_holds_once() -> void:
	var profile := NpcProfile.new()
	profile.id = &"quartermaster"
	profile.dialogue = Dialogue.new()
	profile.dialogue.greeting = _topic(["Hello.", "I keep the guns."])
	var topic: Topic = _topic(["The range is next door."])
	topic.guest_lines = ["Ask the captain."]
	topic.away_lines = ["The range is by the armory."]
	profile.dialogue.topics = [topic]
	profile.tour = Tour.new()
	profile.tour.offer = _topic(["Want to see the ship?"])
	var stop := TourStop.new()
	stop.lines = ["The mess hall.", "Hello."]
	profile.tour.stops = [stop]
	var reaction := CrewReaction.new()
	reaction.lines = ["Good run."]
	profile.reactions = [reaction]
	profile.calls = ["Come by when you dock."]
	assert_eq(profile.spoken_lines().keys(), [&"quartermaster"])
	assert_eq(
		profile.spoken_lines()[&"quartermaster"],
		PackedStringArray(
			[
				Dialogue.DEFAULT_PROMPT,
				"Hello.",
				"I keep the guns.",
				"The range is next door.",
				"Ask the captain.",
				"The range is by the armory.",
				"Want to see the ship?",
				"The mess hall.",
				"Good run.",
				"Come by when you dock.",
			]
		),
		"the default prompt without prompts of their own, a repeated line once"
	)


func test_a_colonist_says_only_its_remarks() -> void:
	var profile := NpcProfile.new()
	profile.id = &"gardener"
	profile.remarks = ["The beans are up.", "Mind the hoses."]
	assert_eq(
		profile.spoken_lines()[&"gardener"],
		PackedStringArray(["The beans are up.", "Mind the hoses."]),
		"no dialogue: no prompt"
	)


func test_lines_from_other_files_count_for_who_says_them() -> void:
	var depot_master := NpcProfile.new()
	depot_master.id = &"depot_master"
	depot_master.remarks = ["Next.", "That's all of it. Thanks."]
	var bartender := NpcProfile.new()
	bartender.id = &"bartender"
	bartender.remarks = ["What'll it be?"]
	var by_speaker: Dictionary[StringName, PackedStringArray] = VoiceLines.lines_by_speaker(
		[depot_master, HandIn.new(), bartender]
	)
	assert_eq(by_speaker.keys(), [&"depot_master", &"bartender"])
	assert_eq(
		by_speaker[&"depot_master"],
		PackedStringArray(["Next.", "That's all of it. Thanks."]),
		"the hand-in's line is the depot master's, once"
	)


func test_every_profile_in_the_game_is_found() -> void:
	var resources: Array[Resource] = VoiceLines.speaking_resources()
	var ids: Array[StringName] = []
	for resource: Resource in resources:
		assert_is(resource, NpcProfile, resource.resource_path)
		ids.append((resource as NpcProfile).id)
	for id: StringName in [&"quartermaster", &"cook", &"bartender", &"councillor", &"gardener"]:
		assert_has(ids, id)
	var spoken: Dictionary[StringName, PackedStringArray] = VoiceLines.lines_by_speaker(resources)
	var quartermaster: NpcProfile = load("res://game/npcs/crew/quartermaster.tres")
	for stop: TourStop in quartermaster.tour.stops:
		for line: String in stop.lines:
			assert_has(spoken[&"quartermaster"], line, "the tour's lines")
	assert_false(spoken[&"gardener"].is_empty(), "a colonist's remarks")


func _topic(lines: Array[String]) -> Topic:
	var topic := Topic.new()
	topic.lines = lines
	return topic
