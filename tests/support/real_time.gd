extends RefCounted
## Waiting for work that runs in real time (worker threads, background bakes) instead of in frames.
## Tests run with `--fixed-fps 60`, so GUT's `wait_until(..., seconds)` counts simulated seconds,
## which pass far faster than the wall clock: a timeout meant for real-time work runs out before
## the work is done on a busy machine.


## Waits frames until `condition` returns true or `seconds` of wall-clock time have passed, and
## returns whether it became true.
static func wait_until(condition: Callable, seconds: float) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await tree.process_frame
	return true
