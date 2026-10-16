extends GutTest


## The engine running the project (editor, CI) must be the version pinned in `.godot-version`.
func test_engine_matches_pinned_version() -> void:
	var pinned: String = FileAccess.get_file_as_string("res://.godot-version").strip_edges()
	var info: Dictionary = Engine.get_version_info()
	var running: String = "%d.%d" % [info["major"], info["minor"]]
	# Godot names x.y.0 releases "x.y"
	var patch: int = info["patch"]
	if patch > 0:
		running += ".%d" % patch
	assert_eq(running, pinned)
