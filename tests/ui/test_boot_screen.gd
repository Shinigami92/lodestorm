extends GutTest
## The boot screen: the game starts on it, it loads the main scene on a worker thread while its
## ring fills and hands the scene over fading in from black.

const BOOT: PackedScene = preload("res://game/ui/boot/boot_screen.tscn")
## A small scene to load instead of the whole map.
const TARGET := "res://game/ui/title/title_credits.tscn"

var _loaded: Node


func after_each() -> void:
	if is_instance_valid(_loaded):
		_loaded.free()
	_loaded = null


func test_the_game_starts_on_it() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	assert_eq(main_scene, BOOT.resource_path)
	var boot := BOOT.instantiate() as BootScreen
	assert_eq(boot.scene_path, "res://game/maps/main.tscn", "and loads the map")
	boot.free()
	var splash: String = ProjectSettings.get_setting("application/boot_splash/image")
	assert_true(FileAccess.file_exists(splash), "the splash is an image of it")


func test_loads_and_hands_over() -> void:
	var boot := BOOT.instantiate() as BootScreen
	boot.scene_path = TARGET
	boot.changes_scene = false
	boot.loaded.connect(func(scene: Node) -> void: _loaded = scene)
	add_child_autofree(boot)
	assert_eq(boot.progress, 0.0, "the ring starts empty")
	await wait_for_signal(boot.loaded, 5.0)
	assert_not_null(_loaded)
	assert_eq(_loaded.scene_file_path, TARGET)
	assert_eq(boot.progress, 1.0, "the ring is full first")
	var fade: ScreenFade = _fade_in(_loaded)
	assert_not_null(fade, "it fades in from black")
	assert_eq((fade.get_child(0) as ColorRect).color.a, 1.0)


func test_without_a_scene_it_only_shows() -> void:
	var boot := BOOT.instantiate() as BootScreen
	boot.scene_path = ""
	add_child_autofree(boot)
	await wait_process_frames(3)
	assert_false(boot.is_processing())
	assert_eq(boot.progress, 0.0)


func test_fading_in_from_black() -> void:
	var parent := Node.new()
	add_child_autofree(parent)
	var fade: ScreenFade = ScreenFade.from_black(parent, 0.1)
	var black := fade.get_child(0) as ColorRect
	await wait_process_frames(1)
	assert_eq(black.color.a, 1.0, "waits out the first frames")
	await wait_seconds(0.4)
	assert_false(is_instance_valid(fade), "gone once clear")


func _fade_in(scene: Node) -> ScreenFade:
	for child: Node in scene.get_children():
		if child is ScreenFade:
			return child
	return null
