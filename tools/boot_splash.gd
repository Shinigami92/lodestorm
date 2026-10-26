extends SceneTree
## Renders the boot splash (`assets/ui/boot/boot_splash.png`, the project's
## `application/boot_splash/image`): the boot screen (`game/ui/boot/boot_screen.tscn`) with its
## ring empty, so the splash turns into the boot screen without a jump. Run it with
## `tools/boot_splash.sh` after changing the boot screen's look (it needs a window: headless runs
## don't render).

const SCENE := "res://game/ui/boot/boot_screen.tscn"
const OUT := "res://assets/ui/boot/boot_splash.png"
## The splash's size; the engine fits it into the window, keeping its aspect.
const SIZE := Vector2i(3840, 2160)
## Frames to render before taking the image (the glow settles over a few).
const FRAMES: int = 10


func _initialize() -> void:
	_render.call_deferred()


func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	# Loaded at runtime: game scripts refer to autoloads, which don't exist yet while this compiles.
	var boot: Node = (load(SCENE) as PackedScene).instantiate()
	boot.set(&"scene_path", "")
	viewport.add_child(boot)
	for i: int in FRAMES:
		await process_frame
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var error: Error = image.save_png(OUT)
	if error != OK:
		push_error("Can't write %s: %s" % [OUT, error_string(error)])
	else:
		print("Wrote ", OUT)
	quit(error)
