class_name WorldPanel
extends WorldMenu
## A screen in the world showing a menu (`menu`, a Control scene rendered in a SubViewport): a
## terminal's screen, or a station's holo card (see `Station`). While a player uses it (see
## `WorldMenu`), the screen draws over everything (nobody standing in front hides it), and the menu
## takes their input:
## - pointing: the mouse cursor, as a ray from the camera through the screen (`pixel_at`); a VR
##   controller will point the same way;
## - focus: `move_*` and the ui_* directions move the focus between controls, `interact` and
##   `ui_accept` press the focused one (keyboard, gamepad).
## The screen faces local +Z and is unshaded, so it reads in dark rooms. Its texture is rendered
## at about the resolution it covers on screen (zoomed in: sharp text; from afar: no shimmer), the
## menu's layout keeps `pixels_per_meter`.

## Actions that steer the menu while it's open, and the GUI action each one sends.
const NAVIGATION: Dictionary[StringName, StringName] = {
	&"move_forward": &"ui_up",
	&"move_back": &"ui_down",
	&"move_left": &"ui_left",
	&"move_right": &"ui_right",
	&"interact": &"ui_accept",
	&"ui_up": &"ui_up",
	&"ui_down": &"ui_down",
	&"ui_left": &"ui_left",
	&"ui_right": &"ui_right",
	&"ui_accept": &"ui_accept",
}
## Render resolution steps (as a factor of `pixels_per_meter`): half an octave apart, so zooming
## resizes the texture only a few times.
const RESOLUTION_STEP: float = 0.5
const MIN_RESOLUTION: float = 0.125
const MAX_RESOLUTION: float = 2.0
## Render priority of the screen while it's used: after the player's overlays (silhouette and rim
## light, priority 1), so the player in front doesn't show through.
const ON_TOP_PRIORITY: int = 10

## The menu shown on the screen.
@export var menu: PackedScene:
	set(value):
		menu = value
		if is_node_ready():
			_show_menu()
## Size of the screen in m.
@export var size: Vector2 = Vector2(1.2, 0.75)
## The menu's layout size in pixels per m: its controls and fonts are sized for this.
@export var pixels_per_meter: float = 800.0
## Whether the screen shows through where the menu draws nothing (e.g. a card smaller than its
## screen).
@export var transparent: bool = false

## The instanced `menu`.
var content: Control

var _material := StandardMaterial3D.new()
## Whether the last pointer position was on the screen.
var _pointer_inside: bool = false
## GUI actions held down right now.
var _held: Dictionary[StringName, bool] = {}

@onready var _viewport: SubViewport = $Viewport
@onready var _screen: MeshInstance3D = $Screen


func _ready() -> void:
	var layout := Vector2i((size * pixels_per_meter).round())
	_viewport.size_2d_override = layout
	_viewport.size_2d_override_stretch = true
	_viewport.size = layout
	_viewport.transparent_bg = transparent
	# Hidden (e.g. a station's card while nobody uses it), it doesn't render.
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()
	_show_menu()
	var quad := QuadMesh.new()
	quad.size = size
	_screen.mesh = quad
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_texture = _viewport.get_texture()
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_screen.material_override = _material


func _process(_delta: float) -> void:
	_update_resolution()


func _input(event: InputEvent) -> void:
	if not user:
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if point(event as InputEventMouse):
			get_viewport().set_input_as_handled()
		return
	for action: StringName in CLOSE_ACTIONS:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			close()
			return
	var handled: bool = false
	var sent: Array[StringName] = []
	for action: StringName in NAVIGATION:
		var gui_action: StringName = NAVIGATION[action]
		if gui_action in sent or not InputMap.has_action(action):
			continue
		var pressed: bool = event.is_action_pressed(action, gui_action != &"ui_accept")
		if not pressed and not event.is_action_released(action):
			continue
		handled = true
		# A stick sends many events while held: only the first one presses (keys repeat with
		# echo events instead).
		if pressed and _held.get(gui_action, false) and not event.is_echo():
			continue
		_held[gui_action] = pressed
		sent.append(gui_action)
		var press := InputEventAction.new()
		press.action = gui_action
		press.pressed = pressed
		_viewport.push_input(press)
	if handled:
		get_viewport().set_input_as_handled()


func _opened() -> void:
	set_on_top(true)
	if content:
		var first: Control = content.find_next_valid_focus()
		if first:
			first.grab_focus()


func _closed() -> void:
	_viewport.gui_release_focus()
	set_on_top(false)
	_pointer_inside = false
	_held.clear()


## The menu pixel (in its layout size) where a ray hits the front of the screen, or `Vector2.INF`
## where it misses. Rays come from the camera through the mouse cursor (or later a VR controller).
func pixel_at(origin: Vector3, direction: Vector3) -> Vector2:
	var normal: Vector3 = global_basis.z
	if direction.dot(normal) >= 0.0:
		return Vector2.INF
	var hit: Variant = Plane(normal.normalized(), global_position).intersects_ray(origin, direction)
	if hit == null:
		return Vector2.INF
	var local: Vector3 = global_transform.affine_inverse() * (hit as Vector3)
	var uv := Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2.INF
	return uv * Vector2(_viewport.size_2d_override)


## The menu's texture size right now.
func get_resolution() -> Vector2i:
	return _viewport.size


## The panel showing `control` (a control in its menu), or null.
static func showing(control: Control) -> WorldPanel:
	return control.get_viewport().get_parent() as WorldPanel


## Passes a mouse event on to the menu where the cursor points at the screen. Returns whether it
## points at the screen.
func point(event: InputEventMouse) -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return false
	var pixel: Vector2 = pixel_at(
		camera.project_ray_origin(event.position), camera.project_ray_normal(event.position)
	)
	var inside: bool = pixel != Vector2.INF
	if not inside and not _pointer_inside:
		return false
	var moved := event.duplicate() as InputEventMouse
	# Off the screen: one last move far outside the menu, so nothing stays hovered.
	moved.position = pixel if inside else Vector2(-1000.0, -1000.0)
	moved.global_position = moved.position
	_pointer_inside = inside
	_viewport.push_input(moved, true)
	return inside


func _show_menu() -> void:
	if content:
		content.queue_free()
		content = null
	if menu:
		content = menu.instantiate() as Control
		_viewport.add_child(content)


func _on_visibility_changed() -> void:
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_WHEN_VISIBLE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	)


## Draws the screen over everything else (the player in front of it), e.g. while it's used.
func set_on_top(on_top: bool) -> void:
	_material.no_depth_test = on_top
	_material.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
		if on_top or transparent
		else BaseMaterial3D.TRANSPARENCY_DISABLED
	)
	_material.render_priority = ON_TOP_PRIORITY if on_top else 0


## Renders the menu at about as many pixels as the screen covers on the display.
func _update_resolution() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera or not _screen.is_visible_in_tree():
		return
	var top: Vector3 = to_global(Vector3(0.0, size.y * 0.5, 0.0))
	var bottom: Vector3 = to_global(Vector3(0.0, -size.y * 0.5, 0.0))
	var left: Vector3 = to_global(Vector3(-size.x * 0.5, 0.0, 0.0))
	var right: Vector3 = to_global(Vector3(size.x * 0.5, 0.0, 0.0))
	for corner: Vector3 in [top, bottom, left, right]:
		if camera.is_position_behind(corner):
			return
	var on_screen := Vector2(
		camera.unproject_position(left).distance_to(camera.unproject_position(right)),
		camera.unproject_position(top).distance_to(camera.unproject_position(bottom))
	)
	# The window may show the viewport stretched (e.g. its base size 1080p on a 4K display).
	on_screen *= get_viewport().get_screen_transform().get_scale()
	var wanted: float = maxf(on_screen.x / size.x, on_screen.y / size.y) / pixels_per_meter
	var steps: float = roundf(log(maxf(wanted, 0.0001)) / log(2.0) / RESOLUTION_STEP)
	var factor: float = clampf(pow(2.0, steps * RESOLUTION_STEP), MIN_RESOLUTION, MAX_RESOLUTION)
	var resolution := Vector2i((Vector2(_viewport.size_2d_override) * factor).round())
	if resolution != _viewport.size:
		_viewport.size = resolution
