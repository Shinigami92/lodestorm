extends GutTest
## The calls that help a new crew survive (`SurvivalCalls`): the gear a region needs and a
## player has, Tamsin's warning about a rough destination once per step, what she knows, her call
## landing in a harder region once, Brannik's miner hint on the first landing and his call after
## the first lost run, Ilse's call to a badly hurt player out of the fight, and Brannik's to a
## player out of spares with no ore.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const RADIO := preload("res://tests/support/radio_wait.gd")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const QUARTERMASTER: String = "Rooms/Lower/Armory/Quartermaster"
const PILOT: String = "Rooms/Upper/Bridge/Pilot"
const MEDIC: String = "Rooms/Lower/MedicalBay/Medic"

var _map: Node3D
var _ship: Ship
var _player: Player
var _survival: SurvivalCalls


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_ship = _map.get_node("Ship") as Ship
	_player = _map.get_node("Player") as Player
	_survival = _ship.reactions.survival
	await wait_physics_frames(2)


func test_the_gear_a_region_needs() -> void:
	var easy := MissionBrief.Difficulty.EASY
	var normal := MissionBrief.Difficulty.NORMAL
	var hard := MissionBrief.Difficulty.HARD
	assert_eq(SurvivalCalls.gear_needed(1, easy), 0)
	assert_eq(SurvivalCalls.gear_needed(1, normal), 1)
	assert_eq(SurvivalCalls.gear_needed(1, hard), 3)
	assert_eq(SurvivalCalls.gear_needed(2, easy), 3)
	assert_eq(SurvivalCalls.gear_needed(6, hard), 18)


func test_gear_counts_armor_and_weapons_not_miners() -> void:
	assert_eq(SurvivalCalls.gear_of(_player), 0, "a new player")
	_player.upgrades.levels[_player.armor_upgrade] = 3
	_player.upgrades.levels[DRILL] = 2
	assert_eq(SurvivalCalls.gear_of(_player), 2, "two armor levels, the drill doesn't count")


func test_a_rough_destination_warns_once_per_step() -> void:
	_choose(&"mire")
	assert_eq(_caller(), "Tamsin · Radio")
	var pilot: NpcProfile = _profile(PILOT)
	assert_eq(
		_player.radio.get_line(), pilot.reaction_lines(CrewReactions.DESTINATION_ROUGH, &"mire")[0]
	)
	assert_true(_ship.story.is_set(&"event.destination_rough.1"))
	await RADIO.quiet(self, _player)
	_choose(&"rimeback")
	assert_eq(_player.radio.get_line(), "", "the same step warns once")
	_choose(&"cinder")
	assert_eq(_caller(), "Tamsin · Radio", "a harder step warns again")


func test_no_warning_with_the_gear_for_it() -> void:
	_player.upgrades.levels[_player.armor_upgrade] = 2
	_choose(&"mire")
	assert_eq(_player.radio.get_line(), "")
	_choose(&"redscar")
	assert_eq(_player.radio.get_line(), "", "an easy region needs nothing")


func test_what_the_pilot_knows() -> void:
	assert_true(_survival.knows(_region(&"mire")), "the colony's own ground")
	assert_true(_survival.knows(_region(&"rimeback")), "its moon too")
	assert_false(_survival.knows(_region(&"glare")))
	_ship.story.set_flag(&"bartender.vehra")
	assert_true(_survival.knows(_region(&"glare")), "talked about at the bar")
	assert_false(_survival.knows(_region(&"brine")))
	_ship.director.regions_visited.append(&"brine")
	assert_true(_survival.knows(_region(&"brine")), "visited before")


func test_landing_in_a_known_harder_region_calls_once() -> void:
	_ship.story.set_flag(&"event.destination_rough.1")
	_ship.story.set_flag(StringName("event.%s" % CrewReactions.MINER_HINT))
	_ship.story.set_flag(&"event.landed.torvane")
	_ship.voyage.select(_ship.voyage.offer_for(_region(&"mire")))
	_ship.voyage.skip_flight()
	await wait_physics_frames(2)
	assert_eq(_player.radio.get_line(), "", "not on landing")
	_ship.player_left.emit(_player)
	assert_eq(_caller(), "Tamsin · Radio")
	assert_eq(
		_player.radio.get_line(),
		_profile(PILOT).reaction_lines(CrewReactions.REGION_LANDING, &"mire")[0]
	)
	assert_true(_ship.story.is_set(&"event.region.mire"))
	await RADIO.quiet(self, _player)
	_ship.player_left.emit(_player)
	assert_eq(_player.radio.get_line(), "", "once per region")


func test_the_first_landing_brings_the_miner_hint() -> void:
	TEST_MAP.pick_mission(_map)
	await wait_physics_frames(2)
	var body: CelestialBody = _ship.voyage.at_body
	_ship.story.set_flag(StringName("event.landed.%s" % body.id))
	_ship.player_left.emit(_player)
	assert_eq(_caller(), "Brannik · Radio")
	assert_eq(
		_player.radio.get_line(),
		_profile(QUARTERMASTER).reaction_lines(CrewReactions.MINER_HINT)[0]
	)
	await RADIO.quiet(self, _player)
	_ship.player_left.emit(_player)
	assert_eq(_player.radio.get_line(), "", "once per game")


func test_the_first_lost_run_is_called_in_once_everyone_is_up() -> void:
	GameEvents.bus.mission_ended.emit(null, false)
	assert_eq(_player.radio.get_line(), "", "not while they lie in the medical bay")
	GameEvents.bus.player_respawned.emit(_player)
	assert_eq(_caller(), "Brannik · Radio")
	assert_eq(
		_player.radio.get_line(),
		_profile(QUARTERMASTER).reaction_lines(CrewReactions.FIRST_RUN_LOST)[0]
	)
	await RADIO.quiet(self, _player)
	GameEvents.bus.mission_ended.emit(null, false)
	GameEvents.bus.player_respawned.emit(_player)
	assert_eq(_player.radio.get_line(), "", "only the first one")


func test_a_badly_hurt_player_out_of_the_fight_hears_ilse() -> void:
	await _step_out()
	_player.vitals.restore(_player.max_health() * 0.2)
	_survival._physics_process(SurvivalCalls.CALM_TIME * 0.5)
	assert_eq(_player.radio.get_line(), "", "not in the fight's first seconds")
	GameEvents.bus.player_hurt.emit(_player, 1.0, null)
	_survival._physics_process(SurvivalCalls.CALM_TIME * 0.6)
	assert_eq(_player.radio.get_line(), "", "a hit starts the calm over")
	_survival._physics_process(SurvivalCalls.CALM_TIME * 0.6)
	assert_eq(_caller(), "Ilse · Radio")
	assert_eq(_player.radio.get_line(), _profile(MEDIC).reaction_lines(CrewReactions.LOW_HEALTH)[0])
	_survival._physics_process(SurvivalCalls.CALM_TIME * 2.0)
	var said: int = _ship.reactions.said.get(&"medic.low_health", 0)
	assert_eq(said, 1, "once per run")


func test_the_last_spares_gone_with_no_ore_on_the_back() -> void:
	await _step_out()
	var ammo: WeaponAmmo = _player.arms.get_ammo()
	assert_not_null(ammo, "the starting weapon takes ammo")
	ammo.spare_rounds = 10
	_survival._physics_process(0.0)
	ammo.spare_rounds = 0
	_survival._physics_process(0.0)
	assert_eq(_caller(), "Brannik · Radio")
	assert_eq(
		_player.radio.get_line(),
		_profile(QUARTERMASTER).reaction_lines(CrewReactions.OUT_OF_SPARES)[0]
	)
	assert_true(_player.hints.is_seen(SurvivalCalls.OUT_OF_SPARES_HINT), "once per player")


func _profile(path: String) -> NpcProfile:
	return (_ship.get_node(path) as Npc).profile


func _region(id: StringName) -> Region:
	for body: CelestialBody in _ship.voyage.settings.system.bodies:
		for region: Region in body.regions:
			if region.id == id:
				return region
	return null


## Chooses the mission on offer for the region `id` as the destination.
func _choose(id: StringName) -> void:
	assert_true(_ship.voyage.choose(_ship.voyage.offer_for(_region(id))), String(id))


## Puts the player outside the ship, a run underway.
func _step_out() -> void:
	_player.global_position = _ship.to_global(Vector3(30.0, 1.0, 0.0))
	_player.reset_physics_interpolation()
	await wait_physics_frames(3)
	assert_false(_ship.is_aboard(_player))
	_ship.voyage.mission.state = Mission.State.RUNNING


## Who the local player's radio bubble says is calling, or "" while it shows nothing.
func _caller() -> String:
	var bubble := _player.radio.panel.content as RadioBubble
	return bubble.get_caller() if _player.radio.panel.visible else ""
