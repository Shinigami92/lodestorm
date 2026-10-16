extends SceneTree
## Gives every scene and resource (`.tscn`, `.tres`) its own UID and every `ext_resource` in them
## the UID of the file it points at, as the editor does when it saves them. Hand-written or
## hand-patched files miss them; a copied file keeps its original's UID and gets a new one.
## Run it with `tools/uids.sh` after adding or changing those files without the editor
## (`tests/test_resource_uids.gd` fails until then). Only the UIDs are added; nothing else changes.

## Not part of the game: third-party code, caches and local scratch files.
const SKIPPED_DIRS: Array[String] = ["res://addons", "res://.godot", "res://local", "res://tmp"]

var _header: RegEx = RegEx.create_from_string("^\\[gd_\\w+ [^\\n]*\\]")
var _header_uid: RegEx = RegEx.create_from_string(' uid="(uid://\\w+)"')
var _ext_resource: RegEx = RegEx.create_from_string("(?m)^\\[ext_resource [^\\n]*\\]$")
var _ext_path: RegEx = RegEx.create_from_string(' path="([^"]+)"')
## UIDs given out in this run, by path (not in the UID cache until the project is imported again).
var _new_uids: Dictionary[String, String] = {}


func _initialize() -> void:
	var paths: Array[String] = _find_resources("res://")
	var own: int = 0
	for path: String in paths:
		own += _give_own_uid(path)
	var refs: int = 0
	var missing: Array[String] = []
	for path: String in paths:
		refs += _fix_references(path, missing)
	print("UIDs: %d files got their own, %d references fixed" % [own, refs])
	for target: String in missing:
		printerr("UIDs: no uid for %s (missing file?)" % target)
	quit(1 if missing else 0)


## Adds a UID to the file's header when it has none, or replaces one that belongs to another file
## (a copy). Returns 1 when the file changed.
func _give_own_uid(path: String) -> int:
	var text: String = FileAccess.get_file_as_string(path)
	var header: RegExMatch = _header.search(text)
	if not header:
		printerr("UIDs: %s has no gd_scene/gd_resource header" % path)
		return 0
	var line: String = header.get_string()
	var found: RegExMatch = _header_uid.search(line)
	if found and _uid_path(found.get_string(1)) in [path, ""]:
		return 0
	var id: int = ResourceUID.create_id()
	ResourceUID.add_id(id, path)
	var uid: String = ResourceUID.id_to_text(id)
	_new_uids[path] = uid
	var new_line: String = (
		line.replace(found.get_string(), ' uid="%s"' % uid)
		if found
		else line.trim_suffix("]") + ' uid="%s"]' % uid
	)
	_write(path, new_line + text.substr(line.length()))
	return 1


## Puts the target's UID into every ext_resource that has none or a wrong one. Returns the number
## of fixed references; targets without a UID go into `missing`.
func _fix_references(path: String, missing: Array[String]) -> int:
	var text: String = FileAccess.get_file_as_string(path)
	var fixed: int = 0
	var result: String = ""
	var last: int = 0
	for ext: RegExMatch in _ext_resource.search_all(text):
		var line: String = ext.get_string()
		var target: String = _ext_path.search(line).get_string(1)
		var uid: String = _uid_of(target)
		var found: RegExMatch = _header_uid.search(line)
		var new_line: String = line
		if not uid:
			if target not in missing:
				missing.append(target)
		elif not found:
			new_line = line.replace(' path="', ' uid="%s" path="' % uid)
		elif found.get_string(1) != uid:
			new_line = line.replace(found.get_string(), ' uid="%s"' % uid)
		if new_line != line:
			fixed += 1
		result += text.substr(last, ext.get_start() - last) + new_line
		last = ext.get_end()
	if fixed:
		_write(path, result + text.substr(last))
	return fixed


func _uid_of(path: String) -> String:
	if path in _new_uids:
		return _new_uids[path]
	var id: int = ResourceLoader.get_resource_uid(path)
	return ResourceUID.id_to_text(id) if id != ResourceUID.INVALID_ID else ""


func _uid_path(uid: String) -> String:
	var id: int = ResourceUID.text_to_id(uid)
	return ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


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
