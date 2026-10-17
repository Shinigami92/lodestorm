extends GutTest
## Only the expected engine warnings are let through (`tests/support/expected_engine_warnings.gd`).

const EXPECTED_ENGINE_WARNINGS := preload("res://tests/support/expected_engine_warnings.gd")
const JOLT_JOBS: String = (
	"Jolt Physics job system exceeded the maximum number of jobs. This should not happen. Please"
	+ " report this. Waiting for jobs to become available..."
)


func test_jolt_job_warning_does_not_fail_the_test() -> void:
	assert_not_null(EXPECTED_ENGINE_WARNINGS.instance, "registered by the pre-run hook")
	var handled: bool = _warn(JOLT_JOBS).handled
	assert_true(handled)


func test_other_warnings_still_count() -> void:
	var tracked: GutTrackedError = _warn("Something else went wrong")
	var handled: bool = tracked.handled
	assert_false(handled)
	tracked.handled = true


func test_jolt_job_error_still_counts() -> void:
	var tracked: GutTrackedError = _warn(JOLT_JOBS, Logger.ERROR_TYPE_ERROR)
	var handled: bool = tracked.handled
	assert_false(handled)
	tracked.handled = true


## An engine warning (or error) as Godot reports it: GUT's tracker first, then the others.
func _warn(text: String, error_type: int = Logger.ERROR_TYPE_WARNING) -> GutTrackedError:
	var backtraces: Array[ScriptBacktrace] = []
	var tracker := gut.error_tracker as GutErrorTracker
	var tracked: GutTrackedError = tracker.add_error(
		"CreateJob", "jolt_job_system.cpp", 123, text, "", false, error_type, backtraces
	)
	EXPECTED_ENGINE_WARNINGS.instance._log_error(
		"CreateJob", "jolt_job_system.cpp", 123, text, "", false, error_type, backtraces
	)
	return tracked
