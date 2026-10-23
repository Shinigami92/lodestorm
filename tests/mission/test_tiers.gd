extends GutTest
## Bodies farther in are harder: stronger aliens, more nests, an earlier warning and a harsher
## storm (see GAME_DESIGN.md, Missions, Tiers).

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const NEST_SCENE: PackedScene = preload("res://game/aliens/nest/alien_nest.tscn")

var _map: Node3D
var _mission: Mission
var _voyage: Voyage
var _settings: MissionSettings
var _voyage_settings: VoyageSettings
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_mission = _map.get_node("Mission") as Mission
	_voyage = _map.get_node("Voyage") as Voyage
	_settings = _mission.settings
	_voyage_settings = _voyage.settings
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func test_tier_1_keeps_the_settings() -> void:
	TEST_MAP.pick_mission(_map)
	assert_eq(_mission.tier(), 1)
	assert_eq(_mission.warning_time(), _settings.warning_time)
	assert_eq(_settings.storm_growth_at(1), _settings.storm_damage_growth)
	assert_eq(_settings.alien_health_at(1), 1.0)
	assert_eq(_settings.alien_damage_at(1), 1.0)
	for difficulty: MissionBrief.Difficulty in MissionBrief.Difficulty.values():
		assert_eq(
			_voyage_settings.nest_factor_at(difficulty, 1),
			_voyage_settings.nest_factors[difficulty]
		)


func test_no_body_counts_as_tier_1() -> void:
	assert_null(_voyage.brief)
	assert_eq(_mission.tier(), 1)


func test_each_tier_scales_aliens_nests_and_the_storm() -> void:
	var offer: MissionBrief = _open_offer_of_tier(6)
	assert_not_null(offer, "Zairen's regions")
	_voyage.select(offer)
	_voyage.skip_flight()
	assert_eq(_mission.tier(), 6)
	# Five tiers above the first.
	assert_almost_eq(_settings.alien_health_at(6), 1.0 + 5 * _settings.alien_health_per_tier, 1e-5)
	assert_almost_eq(_settings.alien_damage_at(6), 1.0 + 5 * _settings.alien_damage_per_tier, 1e-5)
	var nests: float = (
		_voyage_settings.nest_factors[offer.difficulty]
		* (1.0 + 5 * _voyage_settings.nests_per_tier)
	)
	assert_almost_eq(_voyage_settings.nest_factor_at(offer.difficulty, 6), nests, 1e-5)
	assert_eq(_mission.warning_time(), _settings.warning_time + 5 * _settings.warning_time_per_tier)
	_mission.storm_time = 2.0
	var growth: float = _settings.storm_damage_growth * (1.0 + 5 * _settings.storm_growth_per_tier)
	assert_almost_eq(
		_mission.storm_damage_per_second(), _settings.storm_damage + growth * 2.0, 1e-5
	)


func test_design_values_from_torvane_to_zairen() -> void:
	# The design's starting values (TBD, playtest): a 60 s warning on Torvane and 110 s on Zairen,
	# the storm's growth from 2 to 4.5 HP/s per second.
	assert_eq(_settings.warning_time_at(1), 60.0)
	assert_eq(_settings.warning_time_at(6), 110.0)
	assert_almost_eq(_settings.storm_growth_at(1), 2.0, 1e-5)
	assert_almost_eq(_settings.storm_growth_at(6), 4.5, 1e-5)


func test_aliens_hatch_stronger_farther_in() -> void:
	_voyage.select(_open_offer_of_tier(3))
	_voyage.skip_flight()
	var nest := NEST_SCENE.instantiate() as AlienNest
	nest.position = _ship.to_global(Vector3(55.0, 0.0, 0.0))
	_map.add_child(nest)
	await wait_physics_frames(2)
	var alien: Alien = nest.hatch(Alien.Role.HUNTER)
	assert_eq(alien.health_factor, _settings.alien_health_at(3))
	assert_eq(alien.damage_factor, _settings.alien_damage_at(3))
	assert_gt(alien.health_factor, 1.0)
	assert_almost_eq(alien.max_health(), alien.strain.max_health * alien.health_factor, 1e-4)
	assert_eq(alien.health, alien.max_health(), "hatches unhurt")
	var bite: AlienAttack = alien.strain.attacks.back()
	var expected: float = bite.damage * alien.damage_factor
	var player := _map.get_node("Player") as Player
	var before: float = player.health
	alien.strike(player, bite.damage)
	assert_almost_eq(player.health, before - expected, 1e-4)


func _open_offer_of_tier(tier: int) -> MissionBrief:
	while _ship.heat_shield.install_next():
		pass
	for offer: MissionBrief in _voyage.offers:
		var body: CelestialBody = _voyage_settings.system.body_of(offer.region)
		if body and body.tier == tier:
			return offer
	return null
