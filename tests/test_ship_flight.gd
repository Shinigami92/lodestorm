extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")
const MAP: PackedScene = preload("res://scenes/maps/test_map.tscn")
const LOCATION: PackedScene = preload("res://scenes/locations/test_location.tscn")
const GENERATED: PackedScene = preload("res://scenes/locations/generated_location.tscn")
## Seconds every flight phase takes in these tests.
const PHASE_TIME: float = 0.2

var _map: Node3D
var _player: Player
var _mission: Mission
var _ship: Ship
var _flight: ShipFlight


## The game's map (starting in space); every location the ship lands at is a test location.
func _start_in_space() -> void:
	_map = MAP.instantiate() as Node3D
	(_map.get_node("Mission") as Mission).location_scene = LOCATION
	await _start()


## The test map, landed at a test location.
func _start_landed() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	await _start()


func _start() -> void:
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_mission = _map.get_node("Mission") as Mission
	_ship = _map.get_node("Ship") as Ship
	_ship.ramp_duration = 0.25
	_flight = _ship.flight
	var settings := _flight.settings.duplicate() as FlightSettings
	settings.departure_time = PHASE_TIME
	settings.descent_time = PHASE_TIME
	settings.touchdown_time = PHASE_TIME
	settings.takeoff_delay = PHASE_TIME
	settings.takeoff_time = PHASE_TIME
	_flight.settings = settings
	watch_signals(_flight)
	await wait_physics_frames(2)


func test_game_starts_in_space() -> void:
	await _start_in_space()
	assert_eq(_flight.phase, ShipFlight.Phase.SPACE)
	assert_null(_mission.location, "nothing outside")
	assert_null(_map.get_node_or_null("Location"))
	assert_eq(_flight.space_amount(), 1.0)
	assert_false(_ship.ramp_button.enabled)
	assert_eq(_ship.countdown_text, "No mission")
	var environment: Environment = (
		(_map.get_node("WorldEnvironment") as WorldEnvironment).environment
	)
	assert_eq(environment.background_mode, Environment.BG_SKY)
	var sky := environment.sky.sky_material as ShaderMaterial
	var space: float = sky.get_shader_parameter(&"space")
	assert_eq(space, 1.0, "stars all around")


func test_flies_from_space_to_the_location() -> void:
	await _start_in_space()
	var offer: MissionBrief = _mission.offers[1]
	assert_true(_mission.select(offer))
	assert_eq(_flight.phase, ShipFlight.Phase.DEPARTURE)
	await wait_physics_frames(2)
	assert_eq(_ship.countdown_text, "In flight")
	assert_false(_ship.ramp_button.enabled, "no ramp in flight")
	await _wait_for_phase(ShipFlight.Phase.DESCENT)
	assert_null(_mission.location, "still above the clouds")
	await _wait_for_phase(ShipFlight.Phase.TOUCHDOWN)
	assert_not_null(_mission.location, "under the clouds now")
	assert_eq(_mission.location, _map.get_node("Location"))
	assert_almost_eq(_mission.location.global_position, _ship.global_position, Vector3.ONE * 0.001)
	await _wait_for_phase(ShipFlight.Phase.LANDED)
	assert_signal_emit_count(_flight, "landed", 1)
	assert_eq(_mission.brief, offer)
	await wait_physics_frames(2)
	assert_true(_ship.ramp_button.enabled)


func test_takes_off_before_flying_to_the_next_location() -> void:
	await _start_landed()
	var old_location: Node3D = _mission.location
	assert_eq(_flight.phase, ShipFlight.Phase.LANDED)
	assert_true(_mission.select(_mission.offers[0]))
	assert_eq(_flight.phase, ShipFlight.Phase.TAKEOFF)
	assert_eq(_mission.location, old_location, "still on the ground")
	await _wait_for_phase(ShipFlight.Phase.DEPARTURE)
	assert_signal_emit_count(_flight, "left_location", 1)
	assert_null(_mission.location, "left behind")
	await wait_physics_frames(1)
	assert_false(is_instance_valid(old_location))
	await _wait_for_phase(ShipFlight.Phase.LANDED)
	assert_not_null(_mission.location)
	assert_ne(_mission.location, old_location)


func test_ramp_and_picking_wait_for_the_landing() -> void:
	await _start_in_space()
	_mission.select(_mission.offers[0])
	assert_false(_mission.can_select(), "no picking in flight")
	assert_false(_mission.preview(_mission.offers[1]))
	_ship.ramp_button.use(_player)
	assert_eq(_mission.state, Mission.State.CLOSED)
	_mission.skip_flight()
	assert_eq(_flight.phase, ShipFlight.Phase.LANDED)
	assert_true(_mission.can_select())
	await wait_physics_frames(2)
	_ship.ramp_button.use(_player)
	assert_eq(_mission.state, Mission.State.OPEN)


func test_preview_shows_the_location_before_setting_course() -> void:
	await _start_in_space()
	var table: HoloTable = _ship.get_node("Rooms/Upper/Bridge/HoloTable") as HoloTable
	var offer: MissionBrief = _mission.offers[2]
	assert_true(_mission.preview(offer))
	assert_eq(_mission.previewed, offer)
	assert_null(_mission.brief, "no course set yet")
	assert_eq(_flight.phase, ShipFlight.Phase.SPACE)
	assert_gt(table.get_markers().size(), 0, "the ore fields show")
	assert_gt(table.get_node("Hologram/Content").get_child_count(), 0)
	assert_true(_mission.can_confirm())
	assert_true(_mission.confirm())
	assert_eq(_mission.brief, offer)
	assert_false(_mission.can_confirm())
	assert_eq(_flight.phase, ShipFlight.Phase.DEPARTURE)


func test_descent_waits_for_the_location() -> void:
	await _start_in_space()
	_flight.destination_ready = false
	_flight.fly()
	await _wait_for_phase(ShipFlight.Phase.DESCENT)
	await wait_seconds(PHASE_TIME * 3.0)
	assert_eq(_flight.phase, ShipFlight.Phase.DESCENT, "nothing to land on yet")
	_flight.destination_ready = true
	await _wait_for_phase(ShipFlight.Phase.TOUCHDOWN)
	assert_signal_emit_count(_flight, "reached_location", 1)


func test_generated_location_is_prepared_in_the_background() -> void:
	_map = MAP.instantiate() as Node3D
	var mission := _map.get_node("Mission") as Mission
	mission.location_scene = _small_generated_location()
	await _start()
	var offer: MissionBrief = _mission.offers[0]
	assert_true(_mission.preview(offer))
	assert_true(_mission.is_preparing(), "planned on a worker thread")
	var table: HoloTable = _ship.get_node("Rooms/Upper/Bridge/HoloTable") as HoloTable
	assert_eq(table.get_markers().size(), 0, "nothing to show yet")
	await wait_until(func() -> bool: return not _mission.is_preparing(), 20.0)
	assert_gt(table.get_markers().size(), 0, "shown once it's ready")
	assert_true(_mission.confirm())
	assert_true(_flight.destination_ready)
	_mission.skip_flight()
	var location := _mission.location as GeneratedLocation
	assert_not_null(location)
	assert_true(location.is_inside_tree())
	assert_eq(location.biome, offer.biome)
	assert_eq(location.world_seed, offer.world_seed)
	assert_eq(location.nest_factor, _mission.settings.nest_factors[offer.difficulty])


func test_freed_while_preparing() -> void:
	_map = MAP.instantiate() as Node3D
	var mission := _map.get_node("Mission") as Mission
	mission.location_scene = _small_generated_location()
	await _start()
	_mission.preview(_mission.offers[0])
	_mission.preview(_mission.offers[1])
	assert_true(_mission.is_preparing())
	_map.free()
	assert_true(true, "no crash, nothing left behind")


func test_takes_off_after_the_run() -> void:
	await _start_landed()
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_physics_frames(ceili(_ship.ramp_duration * Engine.physics_ticks_per_second) + 2)
	await _move(_ship.to_global(Vector3(22.0, 0.0, 0.0)))
	await _move(_ship.to_global(Vector3(10.0, 2.5, 0.0)))
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_eq(_flight.phase, ShipFlight.Phase.LANDED, "waits for the ramp and a moment")
	await _wait_for_phase(ShipFlight.Phase.TAKEOFF)
	assert_true(_ship.is_ramp_up())
	await _wait_for_phase(ShipFlight.Phase.SPACE)
	assert_null(_mission.location)
	assert_eq(_mission.state, Mission.State.CLOSED)
	assert_true(_mission.can_select())


func test_look_follows_the_flight() -> void:
	await _start_in_space()
	var rig: IsoCameraRig = _map.get_node("IsoCameraRig") as IsoCameraRig
	_flight.settings.descent_time = 5.0
	_mission.select(_mission.offers[0])
	await _wait_for_phase(ShipFlight.Phase.DESCENT)
	await wait_seconds(2.0)
	assert_lt(_flight.space_amount(), 1.0)
	assert_gt(_flight.cloud_amount(), 0.5)
	assert_true((_flight.get_node("Clouds") as GPUParticles3D).emitting)
	assert_gt(rig.shake, 0.0, "the hull shakes in the clouds")
	var weather: Weather = _map.get_node("Weather") as Weather
	var env: Environment = weather.environment.environment
	assert_true(env.fog_enabled)
	assert_gt(env.fog_height_density, 0.0, "the clouds hide the ground")
	_mission.skip_flight()
	await wait_physics_frames(2)
	assert_eq(rig.shake, 0.0)
	assert_eq(_flight.cloud_amount(), 0.0)


func test_streaks_in_space() -> void:
	await _start_in_space()
	_flight.settings.departure_time = 2.0
	_mission.select(_mission.offers[0])
	await wait_seconds(1.0)
	assert_gt(_flight.streak_amount(), 0.5)
	assert_true((_flight.get_node("Streaks") as GPUParticles3D).emitting)


## A generated location smaller than the game's, so the tests stay quick.
func _small_generated_location() -> PackedScene:
	var location := GENERATED.instantiate() as GeneratedLocation
	location.size = 240.0
	location.landing_offset = 0.0
	var scene := PackedScene.new()
	scene.pack(location)
	location.free()
	return scene


func _wait_for_phase(phase: ShipFlight.Phase) -> void:
	await wait_until(func() -> bool: return _flight.phase == phase, 5.0)
	assert_eq(_flight.phase, phase)


func _move(target: Vector3) -> void:
	_player.global_position = target
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
