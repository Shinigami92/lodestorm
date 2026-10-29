extends Node
## The base of a screenshot probe, run by `tools/probe.sh <probe.gd>`: a windowed run that sets up a
## scene, plays it and saves screenshots, for what tests can't see (readability, shaders, the log
## during real play). A probe extends this script by path and overrides `run`:
##
##     extends "res://tests/support/probe.gd"
##
##     func run() -> void:
##         var map: Node3D = add_map()
##         await physics_frames(60)
##         await shot("ship")
##
## Probes are strict like every script (typed, `get_node(...) as Node3D`); keep them in `tmp/`.

## Emitted when `run` is over, with the exit code (the loader quits with it).
signal finished(code: int)

## Where `shot` saves its images (set by the loader: `$PROBE_OUT`, default `tmp/probe/`).
var out_dir: String = ProjectSettings.globalize_path("res://tmp/probe")
## The arguments after the probe's path on the command line.
var args: PackedStringArray = []


func _init() -> void:
	# No saves read or written, no title view, and no pause when the window loses focus.
	SaveGame.directory = ""
	TitleView.shows = false
	PausePanel.pause_on_focus_loss = false


func _ready() -> void:
	_run.call_deferred()


## Override: set the scene up, play it, take the shots.
func run() -> void:
	await get_tree().process_frame


## The main map at the small test location (`tests/support/map_fixture.gd`), added as a child.
## `game/maps/main.tscn` itself starts in space.
func add_map() -> Node3D:
	# Loaded here, so a probe without the map doesn't load it.
	var fixture: GDScript = load("res://tests/support/map_fixture.gd")
	var map: Node3D = fixture.call(&"instantiate") as Node3D
	add_child(map)
	return map


## Waits for physics frames (process frames run at the monitor's rate).
func physics_frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


## Waits for `seconds` of game time.
func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Saves the next drawn frame as `<out_dir>/<shot_name>.png`, cropped to `region` if one is given.
## Headless runs draw nothing, so they only print the name.
func shot(shot_name: String, region: Rect2i = Rect2i()) -> void:
	if DisplayServer.get_name() == "headless":
		print("probe: shot %s skipped (headless)" % shot_name)
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if region.has_area():
		image = image.get_region(region)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path: String = out_dir.path_join(shot_name + ".png")
	image.save_png(path)
	print("probe: shot ", path)


func _run() -> void:
	await run()
	finished.emit(0)
