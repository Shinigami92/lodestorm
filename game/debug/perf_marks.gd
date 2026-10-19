class_name PerfMarks
## TEMPORARY profiling marks (step 9 A probe), removed before the PR.

static var avoid: bool = true
static var totals: Dictionary[StringName, int] = {}
static var counts: Dictionary[StringName, int] = {}


static func add(key: StringName, since: int) -> void:
	totals[key] = totals.get(key, 0) + Time.get_ticks_usec() - since
	counts[key] = counts.get(key, 0) + 1


static func clear() -> void:
	totals.clear()
	counts.clear()
