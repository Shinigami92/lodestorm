extends SceneTree
## Runs a screenshot probe (`tools/probe.sh <probe.gd>`): a script extending
## `tests/support/probe.gd`. A script run with `-s` compiles before the autoloads exist, and game
## classes refer to the `Sfx` autoload, so this loader names no game class: it loads the probe once
## the tree runs. A probe that doesn't load quits at once (instead of leaving an empty window), and
## one still running after `--seconds` quits with 124.

const BASE: String = "res://tests/support/probe.gd"

var _started_msec: int = 0
var _seconds: float = 120.0
var _quitting: bool = false


func _initialize() -> void:
	_started_msec = Time.get_ticks_msec()
	var path: String = ""
	var out: String = "tmp/probe"
	var args: PackedStringArray = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--probe="):
			path = arg.trim_prefix("--probe=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--seconds="):
			_seconds = arg.trim_prefix("--seconds=").to_float()
		else:
			args.append(arg)
	_start.call_deferred(path, out, args)


## Wall-clock watchdog: simulated time may stand still, the clock doesn't.
func _process(_delta: float) -> bool:
	if not _quitting and Time.get_ticks_msec() - _started_msec > _seconds * 1000.0:
		_quitting = true
		printerr("probe: still running after %d s, quitting" % _seconds)
		quit(124)
	return false


func _start(path: String, out: String, args: PackedStringArray) -> void:
	await process_frame
	var script: GDScript = null
	if not path.is_empty() and FileAccess.file_exists(path):
		script = load(path) as GDScript
	if script == null or not _is_probe(script):
		printerr(
			(
				"probe: %s doesn't load (missing, a parse error above, or not extending %s)"
				% [path, BASE]
			)
		)
		quit(1)
		return
	var probe: Node = script.new() as Node
	if out.begins_with("res://") or not out.is_absolute_path():
		out = ProjectSettings.globalize_path("res://" + out.trim_prefix("res://"))
	probe.set(&"out_dir", out)
	probe.set(&"args", args)
	probe.connect(&"finished", _on_finished)
	root.add_child(probe)


## Whether `script` and every script it extends compiled, down to the probe base: a script whose
## base failed to compile still passes `can_instantiate()` (and `new()` then fails).
func _is_probe(script: Script) -> bool:
	var base: Script = script
	while base != null:
		if not base.can_instantiate():
			return false
		if base.resource_path == BASE:
			return true
		base = base.get_base_script()
	return false


func _on_finished(code: int) -> void:
	print("probe: done after %.1f s" % ((Time.get_ticks_msec() - _started_msec) / 1000.0))
	quit(code)
