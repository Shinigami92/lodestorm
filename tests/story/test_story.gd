extends GutTest
## Story flags: their naming scheme (they're saved by name), and the NPC content keeping to it.

const CREW_FOLDER: String = "res://game/npcs/crew/"
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")


func test_flag_names_follow_the_scheme() -> void:
	for flag: StringName in [
		&"quartermaster.ammo", &"quest.lost_haul.2", &"reward.lost_haul", &"crew.okoro.joined"
	]:
		assert_true(Story.is_valid_flag(flag), flag)
	for flag: StringName in [
		&"", &"ammo", &"hint_medical_bay", &"Quartermaster.ammo", &"a..b", &"a.b."
	]:
		assert_false(Story.is_valid_flag(flag), flag)


func test_a_flag_outside_the_scheme_is_refused() -> void:
	var story := Story.new()
	story.set_flag(&"heard everything")
	assert_push_error("isn't a flag name")
	assert_true(story.flags.is_empty())
	story.set_flag(&"quartermaster.ammo")
	assert_true(story.is_set(&"quartermaster.ammo"))


## Every crew member has an id, and their topics' ids start with it.
func test_topic_ids_start_with_their_npc() -> void:
	var files: PackedStringArray = DirAccess.get_files_at(CREW_FOLDER)
	assert_gt(files.size(), 0)
	for file: String in files:
		if file.get_extension() != "tres":
			continue
		var profile := load(CREW_FOLDER.path_join(file)) as NpcProfile
		assert_true(Story.is_valid_flag(StringName("%s.x" % profile.id)), "%s: its id" % file)
		var topics: Array[Topic] = profile.dialogue.topics.duplicate()
		if profile.dialogue.greeting:
			topics.append(profile.dialogue.greeting)
		for topic: Topic in topics:
			assert_true(Story.is_valid_flag(topic.id), "%s: %s" % [file, topic.id])
			assert_true(
				String(topic.id).begins_with("%s." % profile.id), "%s: %s" % [file, topic.id]
			)


func test_a_topic_is_open_once_its_flags_are_set_and_its_weapon_owned() -> void:
	var topic := Topic.new()
	topic.requires = [&"quartermaster.greeting"] as Array[StringName]
	var story := Story.new()
	assert_false(topic.is_open(null, story))
	story.set_flag(&"quartermaster.greeting")
	assert_true(topic.is_open(null, story))
	topic.requires_weapon = BRASK
	assert_false(topic.is_open(null, story), "nobody to own it")
