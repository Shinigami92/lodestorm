extends GutTest
## What's the player's own besides their gear: health carries over between runs and sessions (the
## med beds heal), and the one-time hints they've seen; both are saved with the player.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const DIRECTORY: String = "user://test_save_health/"

var _map: Node3D
var _player: Player
var _mission: Mission
var _ship: Ship


func before_each() -> void:
	SaveGame.directory = DIRECTORY
	_clean()
	await _start()


func after_each() -> void:
	_clean()
	SaveGame.directory = ""


func test_health_carries_over_a_restart() -> void:
	TEST_MAP.pick_mission(_map)
	_ship.ramp_duration = 0.25
	_ship.ramp_button.use(_player)
	await wait_physics_frames(ceili(_ship.ramp_duration * Engine.physics_ticks_per_second) + 2)
	await _move(_ship.to_global(Vector3(22.0, 0.0, 0.0)))
	_player.take_damage(35.0)
	await _move(_ship.to_global(Vector3(10.0, 2.5, 0.0)))
	assert_eq(_mission.state, Mission.State.RETURNED)
	await _restart()
	assert_eq(_player.health, _player.max_health() - 35.0, "what the player came back with")


func test_healing_to_full_is_saved() -> void:
	_player.take_damage(50.0)
	await wait_process_frames(1)
	_player.heal()
	await wait_process_frames(1)
	await _restart()
	assert_eq(_player.health, _player.max_health())


func test_a_dead_player_is_saved_with_full_health() -> void:
	_player.take_damage(_player.health)
	var saved: float = SaveGame.player_data(_player)["health"]
	assert_eq(saved, _player.max_health())


## One-time hints are each player's: saved with the player; the one older ship saves kept among
## the story flags moves into the player's save.
func test_hints_are_saved_with_the_player() -> void:
	_player.hints.mark_seen(RampHint.HINT)
	await wait_process_frames(1)
	var hints: Array = _saved(SaveGame.PLAYER_FILE)["hints"]
	assert_eq(hints, [String(RampHint.HINT)])
	var ship_data: Dictionary = {
		"version": SaveGame.VERSION,
		"story": ["quartermaster.greeting", "hint_medical_bay"],
	}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	_write(SaveGame.PLAYER_FILE, JSON.stringify({"version": SaveGame.VERSION}))
	await _restart()
	assert_eq(_ship.story.flags.keys(), [&"quartermaster.greeting"] as Array[StringName])
	assert_true(_player.hints.is_seen(RampHint.HINT), "moved to the player")
	await wait_process_frames(1)
	var story: Array = _saved(SaveGame.SHIP_FILE)["story"]
	assert_eq(story, ["quartermaster.greeting"], "written again without it")


func _start() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_mission = _map.get_node("Mission") as Mission
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func _restart() -> void:
	_map.free()
	await _start()


func _move(target: Vector3) -> void:
	_player.global_position = target
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)


func _saved(file_name: String) -> Dictionary:
	var path: String = SaveGame.save_directory().path_join(file_name)
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _write(file_name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SaveGame.save_directory())
	var file := FileAccess.open(SaveGame.save_directory().path_join(file_name), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean() -> void:
	SaveGame.erase()
	if FileAccess.file_exists(GameSettings.path()):
		DirAccess.remove_absolute(GameSettings.path())
