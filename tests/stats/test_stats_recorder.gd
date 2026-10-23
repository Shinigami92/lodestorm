extends GutTest
## The statistics: what the recorder counts from the game's events, whose events it keeps, the
## session log and the totals over sessions.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const SCALD: WeaponType = preload("res://game/weapons/types/scald/scald.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const DIRECTORY: String = "user://test_stats/"

var _map: Node3D
var _player: Player
var _mission: Mission
var _ship: Ship
var _recorder: StatsRecorder


func before_each() -> void:
	SaveGame.directory = DIRECTORY
	_clean()
	await _start()


func after_each() -> void:
	if is_instance_valid(_map):
		_map.free()
	_clean()
	SaveGame.directory = ""


func test_counters_split_by_their_labels() -> void:
	var counters := StatCounters.new()
	counters.add("kills", ["harl", "swarmer"])
	counters.add("kills", ["harl", "swarmer"])
	counters.add("kills", ["harl", "brute"])
	counters.add("kills", ["brask", "swarmer"])
	counters.add("dashes")
	counters.add("healed", [], 2.5)
	assert_eq(counters.value("kills", ["harl", "swarmer"]), 2.0)
	assert_eq(counters.value("kills", ["harl"]), 3.0, "the sum under a label")
	assert_eq(counters.value("kills"), 4.0)
	assert_eq(counters.value("dashes"), 1.0)
	assert_eq(counters.value("healed"), 2.5)
	assert_eq(counters.value("missing", ["x"]), 0.0)
	var copy := StatCounters.new()
	copy.from_data(JSON.parse_string(JSON.stringify(counters.to_data())) as Dictionary)
	assert_eq(copy.values, counters.values, "they survive JSON")


func test_ids_are_paths_in_game_without_extension() -> void:
	assert_eq(GameEvents.id_of(HARL), "weapons/types/harl/harl")
	assert_eq(GameEvents.id_of(null), "none")


func test_kill_is_credited_to_the_weapon() -> void:
	var alien: Alien = await _spawn_alien()
	var hit := Hit.new(
		alien.health + 1.0, 0.0, 0.0, Vector3.LEFT, alien.get_aim_point(), _player, HARL
	)
	alien.take_hit(hit)
	var labels: Array[String] = [GameEvents.id_of(HARL), GameEvents.id_of(SWARMER)]
	assert_eq(_recorder.totals.value("kills", labels), 1.0)
	assert_eq(_recorder.totals.value("hits", labels), 1.0)
	assert_almost_eq(_recorder.totals.value("damage_dealt", labels), alien.max_health(), 0.01)
	assert_eq(_recorder.totals.value("aliens_appeared", [GameEvents.id_of(SWARMER)]), 1.0)


func test_burning_credits_the_flame() -> void:
	var alien: Alien = await _spawn_alien()
	Burning.ignite(alien, alien.health * 4.0, 1.0, _player, SCALD)
	await wait_physics_frames(roundi(Burning.TICK * Engine.physics_ticks_per_second) + 2)
	assert_true(alien.dead)
	var labels: Array[String] = [GameEvents.id_of(SCALD), GameEvents.id_of(SWARMER)]
	assert_eq(_recorder.totals.value("kills", labels), 1.0)


func test_deaths_nobody_caused_are_not_the_players() -> void:
	var alien: Alien = await _spawn_alien()
	alien.take_damage(alien.health)
	assert_true(alien.dead)
	assert_eq(_recorder.totals.value("kills"), 0.0)


func test_events_of_other_players_are_not_kept() -> void:
	var teammate := PLAYER_SCENE.instantiate() as Player
	teammate.local = false
	_map.add_child(teammate)
	GameEvents.bus.dashed.emit(teammate)
	GameEvents.bus.dashed.emit(_player)
	assert_eq(_recorder.totals.value("dashes"), 1.0)


func test_timed_reloads_are_counted_by_result() -> void:
	var ammo := _player.get_ammo() as MagazineAmmo
	ammo.rounds = 0
	assert_true(ammo.reload(), "a reload started")
	var window: Vector2 = ammo.timing_window()
	ammo.reload_elapsed = ammo.reload_duration * (window.x + window.y) * 0.5
	assert_true(ammo.reload(), "the timing press")
	var weapon: String = GameEvents.id_of(_player.weapon.type)
	assert_eq(_recorder.totals.value("reloads", [weapon, "reload"]), 1.0)
	assert_eq(_recorder.totals.value("reload_presses", [weapon, "hit"]), 1.0)
	assert_eq(_recorder.totals.value("reload_presses", [weapon, "miss"]), 0.0)


func test_a_lost_run_is_logged_with_its_cause() -> void:
	await _open()
	await _move(_ship.to_global(Vector3(22.0, 0.0, 0.0)))
	_player.add_cargo(KYRITE, 40.0)
	_mission.time_left = 0.0
	_mission.storm_time = 1000.0
	await wait_physics_frames(10)
	assert_true(_player.dead)
	assert_eq(_recorder.totals.value("deaths", ["storm"]), 1.0)
	assert_gt(_recorder.totals.value("damage_taken", ["storm"]), 0.0)
	assert_eq(_recorder.totals.value("ore_lost", [GameEvents.id_of(KYRITE)]), 40.0)
	assert_eq(_recorder.totals.value("missions_ended", ["lost"]), 1.0)
	var events: Array[String] = _logged_events()
	for event: String in ["mission_started", "storm_started", "player_hurt", "player_died"]:
		assert_has(events, event)
	var ended: Dictionary = _logged("mission_ended")
	assert_eq(str(ended["result"]), "lost")
	assert_true((ended["counters"] as Dictionary).has("damage_taken"), "the run's counters")
	assert_true(_logged("mission_started").has("gear"), "what the player took along")


func test_returned_haul_and_totals_survive_a_restart() -> void:
	await _open()
	await _move(_ship.to_global(Vector3(22.0, 0.0, 0.0)))
	_player.add_cargo(KYRITE, 150.0)
	await _move(_ship.to_global(Vector3(10.0, 2.5, 0.0)))
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_eq(_recorder.totals.value("ore_hauled", [GameEvents.id_of(KYRITE)]), 150.0)
	assert_eq(str(_logged("mission_ended")["result"]), "returned")
	assert_true(
		FileAccess.file_exists(
			StatsRecorder.stats_directory().path_join(StatsRecorder.TOTALS_FILE)
		),
		"written when the run ended"
	)
	_map.free()
	await _start()
	assert_eq(_recorder.totals.value("sessions"), 2.0)
	assert_eq(_recorder.totals.value("ore_hauled", [GameEvents.id_of(KYRITE)]), 150.0)
	assert_eq(_session_logs().size(), 2)


func test_older_totals_are_kept_and_newer_ones_put_aside() -> void:
	_map.free()
	var path: String = StatsRecorder.stats_directory().path_join(StatsRecorder.TOTALS_FILE)
	_write_totals(path, StatsRecorder.VERSION - 1)
	await _start()
	assert_eq(_recorder.totals.value("sessions"), 4.0, "three before, this one")
	assert_false(FileAccess.file_exists(path + ".corrupt"))
	_map.free()
	_write_totals(path, StatsRecorder.VERSION + 1)
	await _start()
	assert_eq(_recorder.totals.value("sessions"), 1.0)
	assert_true(FileAccess.file_exists(path + ".corrupt"), "kept for a newer game")


func test_old_session_logs_are_deleted() -> void:
	_map.free()
	var sessions: String = _sessions_directory()
	for i: int in StatsRecorder.KEEP_SESSIONS + 3:
		var file := FileAccess.open(
			sessions.path_join("2000-01-%02d_00-00-00.jsonl" % (i + 1)), FileAccess.WRITE
		)
		file.close()
	await _start()
	var logs: Array[String] = _session_logs()
	assert_eq(logs.size(), StatsRecorder.KEEP_SESSIONS)
	assert_false("2000-01-01_00-00-00.jsonl" in logs, "the oldest went")


func test_nothing_is_written_without_a_directory() -> void:
	_map.free()
	_clean()
	SaveGame.directory = ""
	await _start()
	GameEvents.bus.dashed.emit(_player)
	_map.free()
	assert_false(DirAccess.dir_exists_absolute(DIRECTORY.path_join(StatsRecorder.FOLDER)))


func _start() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child(_map)
	_player = _map.get_node("Player") as Player
	_mission = _map.get_node("Mission") as Mission
	_ship = _map.get_node("Ship") as Ship
	_recorder = _map.get_node("StatsRecorder") as StatsRecorder
	_ship.ramp_duration = 0.25
	await wait_physics_frames(2)


func _spawn_alien() -> Alien:
	var alien: Alien = SWARMER.spawn()
	alien.position = _ship.to_global(Vector3(40.0, 0.0, 0.0))
	_map.add_child(alien)
	await wait_physics_frames(1)
	return alien


func _open() -> void:
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_physics_frames(ceili(_ship.ramp_duration * Engine.physics_ticks_per_second) + 2)


func _move(target: Vector3) -> void:
	_player.global_position = target
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)


func _sessions_directory() -> String:
	var sessions: String = StatsRecorder.stats_directory().path_join(StatsRecorder.SESSIONS_FOLDER)
	DirAccess.make_dir_recursive_absolute(sessions)
	return sessions


func _session_logs() -> Array[String]:
	var logs: Array[String] = []
	logs.assign(DirAccess.get_files_at(_sessions_directory()))
	return logs


## The lines of the newest session log so far.
func _log_lines() -> Array[Dictionary]:
	var logs: Array[String] = _session_logs()
	logs.sort()
	var lines: Array[Dictionary] = []
	var text: String = FileAccess.get_file_as_string(_sessions_directory().path_join(logs[-1]))
	for line: String in text.split("\n", false):
		lines.append(JSON.parse_string(line) as Dictionary)
	return lines


func _logged_events() -> Array[String]:
	_recorder.flush_log()
	var events: Array[String] = []
	for line: Dictionary in _log_lines():
		var event: String = line["e"]
		events.append(event)
	return events


## The last line of `event` in the log.
func _logged(event: String) -> Dictionary:
	_recorder.flush_log()
	var found: Dictionary = {}
	for line: Dictionary in _log_lines():
		if line["e"] == event:
			found = line
	return found


func _write_totals(path: String, version: int) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": version, "counters": {"sessions": 3}}))
	file.close()


func _clean() -> void:
	SaveGame.erase()
	if FileAccess.file_exists(GameSettings.path()):
		DirAccess.remove_absolute(GameSettings.path())
	var stats: String = DIRECTORY.path_join(StatsRecorder.FOLDER)
	var sessions: String = stats.path_join(StatsRecorder.SESSIONS_FOLDER)
	for folder: String in [sessions, stats, DIRECTORY]:
		if DirAccess.dir_exists_absolute(folder):
			for file: String in DirAccess.get_files_at(folder):
				DirAccess.remove_absolute(folder.path_join(file))
			DirAccess.remove_absolute(folder)
