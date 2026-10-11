extends GutTest

const TEST_MAP: PackedScene = preload("res://scenes/maps/test_map.tscn")

var _map: Node3D
var _mission: Mission
var _weather: Weather
var _environment: Environment


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_mission = _map.get_node("Mission") as Mission
	_weather = _map.get_node("Weather") as Weather
	_environment = (_map.get_node("WorldEnvironment") as WorldEnvironment).environment
	# Outside, or the mission would end right away with everyone aboard.
	var player: Player = _map.get_node("Player")
	player.global_position = (_map.get_node("Ship") as Ship).to_global(Vector3(22.0, 0.0, 0.0))
	player.reset_physics_interpolation()
	await wait_physics_frames(3)


func test_calm_before_the_mission() -> void:
	assert_eq(_weather.intensity, 0.0)
	assert_false(_environment.fog_enabled)


func test_storm_builds_up_in_warning_time() -> void:
	_mission.state = Mission.State.RUNNING
	_mission.time_left = _mission.settings.warning_time + 10.0
	await wait_process_frames(5)
	assert_eq(_weather.intensity, 0.0, "calm before the warning time")
	_mission.time_left = _mission.settings.warning_time * 0.5
	await wait_seconds(Weather.RISE_TIME * Weather.BUILD_UP + 0.2)
	assert_almost_eq(_weather.intensity, Weather.BUILD_UP * 0.5, 0.03, "halfway through")
	assert_true(_environment.fog_enabled)


func test_storm_rages_when_time_is_up() -> void:
	var sun: DirectionalLight3D = _map.get_node("Sun")
	var calm_sun: float = sun.light_energy
	_mission.state = Mission.State.STORM
	await wait_seconds(Weather.RISE_TIME + 0.2)
	assert_eq(_weather.intensity, 1.0)
	assert_almost_eq(_environment.fog_density, _weather.max_fog, 0.001)
	assert_lt(sun.light_energy, calm_sun)


func test_no_haze_inside_ship() -> void:
	var player: Player = _map.get_node("Player")
	var ship: Ship = _map.get_node("Ship")
	_mission.state = Mission.State.STORM
	await wait_seconds(Weather.RISE_TIME + 0.2)
	assert_true(_environment.fog_enabled)
	player.global_position = ship.to_global(Vector3(0.0, 1.0, 0.0))
	player.reset_physics_interpolation()
	await wait_seconds(Weather.INDOOR_FADE_TIME + 0.2)
	assert_eq(_weather.indoors, 1.0)
	assert_false(_environment.fog_enabled)
	assert_eq(_weather.intensity, 1.0, "the storm still rages outside")


func test_next_run_starts_calm() -> void:
	_weather.intensity = 1.0
	_mission.state = Mission.State.RETURNED
	await wait_process_frames(5)
	assert_eq(_weather.intensity, 1.0, "the storm keeps raging outside")
	(_map.get_node("Ship") as Ship).ramp_button.use(_map.get_node("Player") as Player)
	await wait_process_frames(2)
	assert_eq(_weather.intensity, 0.0)
	assert_false(_environment.fog_enabled)


func test_each_map_has_its_own_environment() -> void:
	var other: Node3D = TEST_MAP.instantiate() as Node3D
	add_child_autofree(other)
	await wait_process_frames(1)
	var other_environment: Environment = (
		(other.get_node("WorldEnvironment") as WorldEnvironment).environment
	)
	assert_ne(other_environment, _environment)
