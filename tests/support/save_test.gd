extends GutTest
## The setup `test_save_format.gd` and `test_save_contents.gd` share: the test map, restarted on
## the save files each script keeps in a directory of its own (they run in parallel).

const TEST_MAP := preload("res://tests/support/map_fixture.gd")

var _map: Node3D
var _player: Player
var _ship: Ship


func before_each() -> void:
	# Named after the script, e.g. user://test_save_format/
	var script_name: String = (get_script() as Script).resource_path.get_file().get_basename()
	SaveGame.directory = "user://%s/" % script_name
	_clean()
	await _start()


func after_each() -> void:
	_clean()
	SaveGame.directory = ""


func _start() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func _restart() -> void:
	_map.free()
	await _start()


func _saved(file_name: String) -> Dictionary:
	var path: String = SaveGame.save_directory().path_join(file_name)
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _uid(resource: Resource) -> String:
	return ResourceUID.path_to_uid(resource.resource_path)


func _write(file_name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SaveGame.save_directory())
	var file := FileAccess.open(SaveGame.save_directory().path_join(file_name), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean() -> void:
	SaveGame.erase()
	if FileAccess.file_exists(GameSettings.path()):
		DirAccess.remove_absolute(GameSettings.path())
