extends GutTest
## The crew's transmissions (`CrewReactions`): who calls in after which event, one crew member a
## call (taking turns), to everyone or only the player it's about, worded for a player alone or
## several, one-time events once, the big haul, the lines in turn, the radio bubble and its queue,
## the storm warning only outside, and what's saved.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const PLAYER_SCENE: String = "res://game/player/player.tscn"
const QUARTERMASTER: String = "Rooms/Lower/Armory/Quartermaster"
const PILOT: String = "Rooms/Upper/Bridge/Pilot"
const MEDIC: String = "Rooms/Lower/MedicalBay/Medic"

var _map: Node3D
var _ship: Ship
var _player: Player
var _reactions: CrewReactions


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_ship = _map.get_node("Ship") as Ship
	_player = _map.get_node("Player") as Player
	_reactions = _ship.reactions
	await wait_physics_frames(2)


func after_each() -> void:
	TranslationServer.set_locale("en")


func test_every_reaction_is_to_a_known_event_with_lines() -> void:
	var events: Array[StringName] = []
	for npc: Npc in _reactions.crew():
		for reaction: CrewReaction in npc.profile.reactions:
			assert_has(CrewReactions.EVENTS, reaction.event, String(npc.profile.id))
			assert_false(reaction.lines.is_empty(), "%s %s" % [npc.profile.id, reaction.event])
			if reaction.event not in events:
				events.append(reaction.event)
	assert_eq(events.size(), CrewReactions.EVENTS.size(), "someone calls about every event")


func test_the_first_run_won_is_called_in_once_when_everyone_is_back() -> void:
	var brannik: NpcProfile = _profile(QUARTERMASTER)
	GameEvents.bus.mission_ended.emit(null, true)
	assert_eq(_caller(), "Brannik · Radio")
	assert_eq(_player.radio.get_line(), brannik.reaction_lines(CrewReactions.FIRST_RUN_WON)[0])
	assert_true(_ship.story.is_set(&"event.first_run_won"))
	await _until_quiet()
	GameEvents.bus.mission_ended.emit(null, true)
	assert_eq(_player.radio.get_line(), "", "only the first one")


func test_alone_or_together_worded_apart() -> void:
	var pilot: NpcProfile = _profile(PILOT)
	var alone: Array[String] = pilot.reaction_lines(CrewReactions.STORM_WARNING, &"", false)
	var together: Array[String] = pilot.reaction_lines(CrewReactions.STORM_WARNING, &"", true)
	assert_ne(alone[0], together[0])
	var brannik: NpcProfile = _profile(QUARTERMASTER)
	assert_ne(
		brannik.reaction_lines(CrewReactions.FIRST_RUN_WON, &"", false),
		brannik.reaction_lines(CrewReactions.FIRST_RUN_WON, &"", true)
	)
	# Lines for either go to both.
	assert_eq(
		brannik.reaction_lines(CrewReactions.BIG_HAUL, &"", false),
		brannik.reaction_lines(CrewReactions.BIG_HAUL, &"", true)
	)


func test_together_everyone_hears_the_coop_wording() -> void:
	var teammate: Player = _add_teammate()
	await wait_physics_frames(2)
	GameEvents.bus.mission_ended.emit(null, true)
	var line: String = (
		_profile(QUARTERMASTER).reaction_lines(CrewReactions.FIRST_RUN_WON, &"", true)[0]
	)
	assert_eq(_player.radio.get_line(), line)
	assert_eq(teammate.radio.get_line(), line)


func test_a_new_weapon_only_to_its_player_with_the_crew_taking_turns() -> void:
	var teammate: Player = _add_teammate()
	await wait_physics_frames(2)
	GameEvents.bus.weapon_unlocked.emit(_player, null)
	var first: String = _caller()
	assert_ne(first, "")
	assert_eq(teammate.radio.get_line(), "", "not for the teammate")
	await _until_quiet()
	GameEvents.bus.weapon_unlocked.emit(_player, null)
	assert_ne(_caller(), first, "the other one's turn")
	assert_has(["Dace · Radio", "Brannik · Radio"], _caller())


func test_the_first_fall_is_called_in_on_waking() -> void:
	var ilse: NpcProfile = _profile(MEDIC)
	GameEvents.bus.player_died.emit(_player, null)
	assert_eq(_player.radio.get_line(), "", "not while down")
	GameEvents.bus.player_respawned.emit(_player)
	assert_eq(_caller(), "Ilse · Radio")
	assert_eq(_player.radio.get_line(), ilse.reaction_lines(CrewReactions.FIRST_DEATH)[0])
	await _until_quiet()
	GameEvents.bus.player_died.emit(_player, null)
	GameEvents.bus.player_respawned.emit(_player)
	assert_eq(_player.radio.get_line(), "", "only the first fall")


func test_calls_wait_their_turn() -> void:
	GameEvents.bus.mission_ended.emit(null, true)
	GameEvents.bus.weapon_unlocked.emit(_player, null)
	GameEvents.bus.weapon_unlocked.emit(_player, null)
	assert_eq(_caller(), "Brannik · Radio")
	assert_eq(_player.radio.waiting_count(), 1, "a newer call about the same replaces the older")
	var first: String = _player.radio.get_line()
	await wait_seconds(Npc.reading_time(first) + PlayerRadio.GAP + 0.3)
	assert_ne(_player.radio.get_line(), "")
	assert_ne(_player.radio.get_line(), first)


func test_a_big_haul_beats_the_biggest_by_a_quarter() -> void:
	_ship.story.set_flag(&"event.first_run_won")
	_run(100.0)
	assert_eq(_reactions.biggest_haul, 100.0, "the first won run sets it")
	assert_eq(_player.radio.get_line(), "", "but isn't big yet")
	_run(120.0)
	assert_eq(_player.radio.get_line(), "", "not a quarter more")
	assert_eq(_reactions.biggest_haul, 120.0)
	_run(150.0)
	assert_ne(_player.radio.get_line(), "")
	assert_eq(_reactions.biggest_haul, 150.0)


func test_lines_said_in_turn() -> void:
	var profile: NpcProfile = _profile(QUARTERMASTER)
	var lines: Array[String] = profile.reaction_lines(CrewReactions.WEAPON_BUILT)
	assert_gt(lines.size(), 1)
	for turn: int in lines.size() + 1:
		var expected: String = lines[turn % lines.size()]
		assert_eq(_reactions.next_line(profile, CrewReactions.WEAPON_BUILT), expected)


func test_a_new_planet_and_the_first_landing_name_the_body() -> void:
	GameEvents.bus.heat_shield_raised.emit(2)
	assert_eq(_caller(), "Okoro · Radio")
	assert_string_contains(_player.radio.get_line(), "Vehra")
	await _until_quiet()
	TEST_MAP.pick_mission(_map)
	await wait_physics_frames(2)
	var body: CelestialBody = _ship.voyage.at_body
	assert_eq(_player.radio.get_line(), "", "not on landing")
	_ship.player_left.emit(_player)
	assert_true(_ship.story.is_set(StringName("event.landed.%s" % body.id)))
	assert_eq(_caller(), "Tamsin · Radio")
	assert_eq(
		_player.radio.get_line(),
		_profile(PILOT).reaction_lines(CrewReactions.FIRST_LANDING, body.id)[0]
	)
	await _until_quiet()
	_ship.player_left.emit(_player)
	assert_eq(_player.radio.get_line(), "", "once per body")


func test_the_storm_warning_only_for_the_players_outside() -> void:
	var pilot: NpcProfile = _profile(PILOT)
	var lines: Array[String] = pilot.reaction_lines(CrewReactions.STORM_WARNING)
	GameEvents.bus.storm_warned.emit()
	assert_eq(_player.radio.get_line(), "", "aboard: no call")
	_player.global_position = _ship.get_boarding_position() + Vector3(20.0, 0.0, 0.0)
	await wait_physics_frames(3)
	assert_false(_ship.is_aboard(_player))
	GameEvents.bus.storm_warned.emit()
	assert_eq(_player.radio.get_line(), lines[0])
	assert_eq(_caller(), "Tamsin · Radio")
	assert_eq(_player.radio.voice.bus, &"Radio")
	await _until_quiet()
	TranslationServer.set_locale("de")
	_reactions.transmit(CrewReactions.STORM_WARNING)
	assert_eq(_caller(), "Tamsin · Funk")
	assert_eq(_player.radio.get_line(), tr(lines[1]), "the next line in turn")


func test_the_mission_warns_when_the_warning_time_starts() -> void:
	var mission := _map.get_node("Mission") as Mission
	watch_signals(GameEvents.bus)
	mission.state = Mission.State.RUNNING
	mission.time_left = mission.warning_time() + 0.01
	await wait_physics_frames(3)
	assert_signal_emit_count(GameEvents.bus, "storm_warned", 1)


func test_saved_and_read_back() -> void:
	GameEvents.bus.weapon_unlocked.emit(_player, null)
	_reactions.next_line(_profile(QUARTERMASTER), CrewReactions.BIG_HAUL)
	_reactions.biggest_haul = 42.5
	var data: Dictionary = JSON.parse_string(JSON.stringify(_reactions.save_data()))
	var other := CrewReactions.new()
	assert_true(other.load_data(data))
	assert_eq(other.save_data(), _reactions.save_data())
	other.free()
	var broken := CrewReactions.new()
	var saved_said: Dictionary = data["said"]
	saved_said["pilot.storm_warning"] = "lots"
	assert_false(broken.load_data(data), "a broken count is skipped")
	assert_eq(broken.said.size(), _reactions.said.size())
	broken.free()


func _profile(path: String) -> NpcProfile:
	return (_ship.get_node(path) as Npc).profile


## Who the local player's radio bubble says is calling, or "" while it shows nothing.
func _caller() -> String:
	var bubble := _player.radio.panel.content as RadioBubble
	return bubble.get_caller() if _player.radio.panel.visible else ""


## Waits until the radio is quiet and nothing waits.
func _until_quiet() -> void:
	for i: int in 3000:
		if _player.radio.get_line().is_empty() and _player.radio.waiting_count() == 0:
			break
		await wait_physics_frames(1)
	await wait_seconds(PlayerRadio.GAP + 0.1)


## A teammate (player 2, not local) next to the player.
func _add_teammate() -> Player:
	var teammate := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	teammate.local = false
	teammate.number = 2
	_player.get_parent().add_child(teammate)
	teammate.global_position = _player.global_position + _player.global_basis.x * 2.5
	teammate.reset_physics_interpolation()
	return teammate


## A won run bringing back `amount` units.
func _run(amount: float) -> void:
	GameEvents.bus.mission_started.emit(null)
	GameEvents.bus.ore_hauled.emit(_player, null, amount)
	GameEvents.bus.mission_ended.emit(null, true)
