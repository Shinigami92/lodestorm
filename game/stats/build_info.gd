class_name BuildInfo
extends RefCounted
## Which code a session runs, for the statistics: the git commit and branch of the project folder,
## read from its `.git` (no git needed on the PATH; a worktree's `.git` file is followed). Empty in
## exported builds and outside a repository. Local changes on top of the commit aren't seen.


## The commit the project folder is on (40 hex digits), or "".
static func commit() -> String:
	return _read()["commit"]


## The branch the project folder is on ("" when detached or unknown).
static func branch() -> String:
	return _read()["branch"]


static func _read() -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {"commit": "", "branch": ""}
	var git_dir: String = _git_dir(ProjectSettings.globalize_path("res://").path_join(".git"))
	if not git_dir:
		return result
	var head: String = _first_line(git_dir.path_join("HEAD"))
	if not head.begins_with("ref: "):
		result["commit"] = head
		return result
	var ref: String = head.trim_prefix("ref: ")
	result["branch"] = ref.trim_prefix("refs/heads/")
	var common: String = _common_dir(git_dir)
	for dir: String in [git_dir, common]:
		var sha: String = _first_line(dir.path_join(ref))
		if sha:
			result["commit"] = sha
			return result
	for line: String in _text(common.path_join("packed-refs")).split("\n", false):
		if line.ends_with(" " + ref):
			result["commit"] = line.get_slice(" ", 0)
	return result


## The git folder behind `dot_git`: itself, or where a worktree's `.git` file points; "" if none.
static func _git_dir(dot_git: String) -> String:
	if DirAccess.dir_exists_absolute(dot_git):
		return dot_git
	var pointer: String = _first_line(dot_git)
	if not pointer.begins_with("gitdir: "):
		return ""
	var target: String = pointer.trim_prefix("gitdir: ")
	return target if target.is_absolute_path() else dot_git.get_base_dir().path_join(target)


## The folder holding the shared refs: a worktree's `commondir`, else the git folder itself.
static func _common_dir(git_dir: String) -> String:
	var common: String = _first_line(git_dir.path_join("commondir"))
	if not common:
		return git_dir
	return common if common.is_absolute_path() else git_dir.path_join(common).simplify_path()


static func _first_line(path: String) -> String:
	return _text(path).get_slice("\n", 0).strip_edges()


static func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
