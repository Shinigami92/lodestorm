class_name BootScreen
extends Node3D
## The first scene (`run/main_scene`): the game's emblem and name in the dark while the main scene
## loads on a worker thread (see docs/design/ui.md). It picks up from the boot splash, which is an
## image of it (`tools/boot_splash.gd`), and the ring around the emblem fills with the loading's
## progress. Once loaded it hands over to the main scene, which fades in from black; until the main
## scene's first frame is drawn, this one's last frame stays on the screen.

## Emitted with the loaded scene, instanced, before it takes over.
signal loaded(scene: Node)

## The scene it loads and hands over to; empty: loads nothing (`tools/boot_splash.gd`).
@export_file("*.tscn") var scene_path: String = "res://game/maps/main.tscn"
## How fast the ring follows the loading, in turns per s, so a quick load still fills it visibly.
@export var fill_speed: float = 1.5
## How long the loaded scene fades in from black, in s.
@export var fade_in_time: float = 0.6
## Whether it changes to the loaded scene (off in the tests, which take it from `loaded`).
@export var changes_scene: bool = true

## How much of the ring is filled, 0..1.
var progress: float = 0.0

var _loaded: float = 0.0
var _status: Array = []

@onready var _ring_material: ShaderMaterial = ($Ring as MeshInstance3D).material_override


func _ready() -> void:
	_show_progress()
	if scene_path.is_empty():
		set_process(false)
		return
	var error: Error = ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	if error != OK:
		push_error("Can't load %s: %s" % [scene_path, error_string(error)])
		set_process(false)


func _process(delta: float) -> void:
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
		scene_path, _status
	)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_loaded = _status[0]
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		_loaded = 1.0
	else:
		push_error("Loading %s failed" % scene_path)
		set_process(false)
		return
	progress = move_toward(progress, _loaded, fill_speed * delta)
	_show_progress()
	if status == ResourceLoader.THREAD_LOAD_LOADED and progress >= 1.0:
		_hand_over()


func _hand_over() -> void:
	set_process(false)
	var packed := ResourceLoader.load_threaded_get(scene_path) as PackedScene
	var scene: Node = packed.instantiate()
	ScreenFade.from_black(scene, fade_in_time)
	loaded.emit(scene)
	if changes_scene:
		get_tree().change_scene_to_node(scene)


func _show_progress() -> void:
	_ring_material.set_shader_parameter(&"progress", progress)
