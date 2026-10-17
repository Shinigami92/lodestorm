extends Logger
## Marks engine warnings that say nothing about the code under test as handled, so GUT doesn't fail
## whichever test happens to run: Jolt's job system waiting for free jobs while every worker thread
## is busy (CI runs four test processes on four cores, and `--fixed-fps` steps physics back to
## back), which Jolt only waits out. Registered by `pre_run.gd` after GUT's own error tracker, so
## the warning is already tracked when this sees it.

const EXPECTED: PackedStringArray = [
	"Jolt Physics job system exceeded the maximum number of jobs",
]

static var instance: Logger


func _log_error(
	_function: String,
	_file: String,
	_line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	_script_backtraces: Array[ScriptBacktrace]
) -> void:
	if error_type != ERROR_TYPE_WARNING or not is_expected(code + " " + rationale):
		return
	var tracker := GutUtils.get_error_tracker() as GutErrorTracker
	for tracked: GutTrackedError in tracker.get_current_test_errors():
		var text: String = "%s %s" % [tracked.code, tracked.rationale]
		if is_expected(text):
			tracked.handled = true


static func is_expected(text: String) -> bool:
	for expected: String in EXPECTED:
		if text.contains(expected):
			return true
	return false
