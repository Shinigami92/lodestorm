extends "res://tests/support/menu_fit.gd"
## Everything the crew and the colonists say fits their bubble and card in every language: their
## topics, radio calls and remarks.

const CREW: Array[NpcProfile] = [
	preload("res://game/npcs/crew/quartermaster.tres"),
	preload("res://game/npcs/crew/pilot.tres"),
	preload("res://game/npcs/crew/engineer.tres"),
	preload("res://game/npcs/crew/medic.tres"),
	preload("res://game/npcs/crew/gunsmith.tres"),
	preload("res://game/npcs/crew/suit_tech.tres"),
	preload("res://game/npcs/crew/miner_mechanic.tres"),
	preload("res://game/npcs/crew/cook.tres"),
]
const ALL_WEAPONS: Arsenal = preload("res://game/weapons/all_weapons.tres")


func test_every_crew_line_and_card_fits_in_every_language() -> void:
	# Topics about a weapon show only to its owners.
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		_player.arsenal.unlock(weapon_type)
	for profile: NpcProfile in CREW:
		await _assert_lines_fit(_ship.get_node(NPCS[profile.resource_path]) as Npc)


func test_every_crew_call_fits_in_every_language() -> void:
	var radio: PlayerRadio = _player.radio
	var bubble := radio.panel.content as RadioBubble
	var layout := Vector2(radio.panel.size * radio.panel.pixels_per_meter)
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		for profile: NpcProfile in CREW:
			for reaction: CrewReaction in profile.reactions:
				for line: String in reaction.lines:
					radio.clear()
					radio.hear(profile, line)
					await wait_process_frames(1)
					var label: String = "%s %s %s %s" % [locale, profile.id, reaction.event, line]
					var needed: Vector2 = bubble.get_needed_size()
					assert_lte(needed.x, layout.x + 0.5, "%s: %s wide" % [label, needed.x])
					assert_lte(needed.y, layout.y + 0.5, "%s: %s high" % [label, needed.y])
	radio.clear()


func test_every_station_line_card_and_remark_fits_in_every_language() -> void:
	var voyage := _map.get_node("Voyage") as Voyage
	voyage.select(voyage.offer_for_station(voyage.settings.system.body_by_id(&"ostra")))
	voyage.skip_flight()
	await wait_physics_frames(2)
	# Every body in reach: every rumor topic open.
	_ship.heat_shield.restore(_ship.heat_shield.max_mk(), false, {})
	var people: Node = voyage.location.get_node("People")
	for person: Node in people.get_children():
		if person is Npc:
			await _assert_lines_fit(person as Npc)
	# The camera zooms back out after the last talk.
	var rig := _map.get_node("IsoCameraRig") as IsoCameraRig
	for i: int in 300:
		if is_equal_approx(rig.zoom, 1.0):
			break
		await wait_process_frames(1)
	for person: Node in people.get_children():
		var colonist := person as Colonist
		if not colonist:
			continue
		for locale: String in SettingsList.languages():
			TranslationServer.set_locale(locale)
			for remark: int in colonist.profile.remarks.size():
				colonist.remark()
				await wait_process_frames(1)
				var label: String = "%s %s remark %d" % [locale, colonist.name, remark + 1]
				_assert_speech_fits(colonist.bubble, label)
				var share: float = _bubble_text_height(colonist.bubble, colonist)
				assert_gte(share, MIN_TEXT_HEIGHT, label + " reads")


## Every line of `npc`'s topics (also the ones for elsewhere) and their card fit in every language.
func _assert_lines_fit(npc: Npc) -> void:
	var profile: NpcProfile = npc.profile
	_player.global_position = npc.use_point.global_position
	var dialogue: Dialogue = profile.dialogue
	var topics: Array[Topic] = dialogue.topics.duplicate()
	topics.push_front(dialogue.greeting)
	for locale: String in SettingsList.languages():
		TranslationServer.set_locale(locale)
		# Every topic open and new (the most buttons, the widest with their dots).
		_ship.story.flags.clear()
		for topic: Topic in topics:
			for flag: StringName in topic.requires:
				_ship.story.flags[flag] = true
		npc.open(_player)
		npc.leave_topic()
		await wait_process_frames(1)
		_assert_card_fits(npc, "%s %s topics" % [locale, profile.display_name])
		_assert_bubble_fits(npc, "%s %s prompt" % [locale, profile.display_name])
		for topic: Topic in topics:
			npc.talk_about(topic)
			for line: int in topic.lines.size():
				await wait_process_frames(1)
				var label: String = "%s %s line %d" % [locale, topic.id, line + 1]
				_assert_card_fits(npc, label)
				_assert_bubble_fits(npc, label)
				npc.advance()
			# What they say outside their own room.
			for line: int in topic.away_lines.size():
				(npc.bubble.content as SpeechBubble).show_line(tr(topic.away_lines[line]))
				await wait_process_frames(1)
				_assert_bubble_fits(npc, "%s %s away line %d" % [locale, topic.id, line + 1])
		npc.close()


func _assert_bubble_fits(npc: Npc, label: String) -> void:
	_assert_speech_fits(npc.bubble, label)


func _assert_speech_fits(panel: WorldPanel, label: String) -> void:
	var speech := panel.content as SpeechBubble
	var needed: Vector2 = speech.get_needed_size()
	var layout := Vector2(panel.size * panel.pixels_per_meter)
	assert_lte(needed.x, layout.x + 0.5, "%s bubble: %s wide" % [label, needed.x])
	assert_lte(needed.y, layout.y + 0.5, "%s bubble: %s high" % [label, needed.y])
