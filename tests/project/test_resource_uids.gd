extends GutTest

## Not part of the game: third-party code, caches and local scratch files.
const SKIPPED_DIRS: Array[String] = ["res://addons", "res://.godot", "res://local", "res://tmp"]

var _header_uid: RegEx = RegEx.create_from_string('^\\[gd_\\w+ [^\\n]*uid="(uid://\\w+)"')
var _ext_resource: RegEx = RegEx.create_from_string("(?m)^\\[ext_resource [^\\n]*\\]$")
var _ext_uid: RegEx = RegEx.create_from_string('uid="(uid://\\w+)"')
var _ext_path: RegEx = RegEx.create_from_string('path="([^"]+)"')


## Every scene and resource has its own UID, and it points back at the file (a copied file keeps
## its original's UID, which then points elsewhere).
func test_scenes_and_resources_have_their_own_uid() -> void:
	var paths: Array[String] = _find_resources("res://")
	assert_gt(paths.size(), 0, "no scenes or resources found")
	for path: String in paths:
		var found: RegExMatch = _header_uid.search(FileAccess.get_file_as_string(path))
		assert_not_null(found, "%s has no uid in its header" % path)
		if found:
			assert_eq(_uid_path(found.get_string(1)), path, "%s: its uid points elsewhere" % path)


## Every reference to another file carries the target's UID next to its path, so a file moved in
## the editor (or by hand, with the paths fixed later) still resolves.
func test_ext_resources_have_the_target_uid() -> void:
	for path: String in _find_resources("res://"):
		var text: String = FileAccess.get_file_as_string(path)
		for ext: RegExMatch in _ext_resource.search_all(text):
			var line: String = ext.get_string()
			var uid: RegExMatch = _ext_uid.search(line)
			var target: String = _ext_path.search(line).get_string(1)
			assert_not_null(uid, "%s: %s has no uid" % [path, target])
			if uid:
				assert_eq(_uid_path(uid.get_string(1)), target, "%s: uid of %s" % [path, target])


func _uid_path(uid: String) -> String:
	var id: int = ResourceUID.text_to_id(uid)
	return ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""


func _find_resources(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	if dir_path in SKIPPED_DIRS or FileAccess.file_exists(dir_path.path_join(".gdignore")):
		return found
	for file: String in DirAccess.get_files_at(dir_path):
		if file.get_extension() in ["tscn", "tres"]:
			found.append(dir_path.path_join(file))
	for dir: String in DirAccess.get_directories_at(dir_path):
		found.append_array(_find_resources(dir_path.path_join(dir)))
	return found
