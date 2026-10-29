extends GutHookScript
## Runs after the tests: stops every sound and gives the audio server a moment of wall-clock time
## before GUT quits. A stopped sound's playback is only let go on the server's next mixes (its own
## thread, in real time), so the last sound of a test process (a step in mud) was still held at exit
## and reported as leaked. Frames don't help: with `--fixed-fps` they pass faster than the mixes.

## How long the audio server gets, in seconds of wall-clock time. A few of its mixes.
const AUDIO_RELEASE: float = 0.25


func run() -> void:
	Sfx.stop_all()
	var tree := Engine.get_main_loop() as SceneTree
	var until: int = Time.get_ticks_msec() + int(AUDIO_RELEASE * 1000.0)
	while Time.get_ticks_msec() < until:
		await tree.process_frame
