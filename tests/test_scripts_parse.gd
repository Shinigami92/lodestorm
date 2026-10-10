extends GutTest

## Not part of the game: third-party code, caches and local scratch files.
const SKIPPED_DIRS: Array[String] = ["res://addons", "res://.godot", "res://local", "res://tmp"]


## Every project script must load. Typing warnings are errors (project settings), so this also
## enforces static typing; GUT itself silently skips test scripts that fail to parse.
func test_all_scripts_load() -> void:
	var paths: Array[String] = _find_scripts("res://")
	assert_gt(paths.size(), 0, "no scripts found")
	for path: String in paths:
		assert_not_null(load(path), path)


func _find_scripts(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	if dir_path in SKIPPED_DIRS or FileAccess.file_exists(dir_path.path_join(".gdignore")):
		return found
	for file: String in DirAccess.get_files_at(dir_path):
		if file.get_extension() == "gd":
			found.append(dir_path.path_join(file))
	for dir: String in DirAccess.get_directories_at(dir_path):
		found.append_array(_find_scripts(dir_path.path_join(dir)))
	return found
