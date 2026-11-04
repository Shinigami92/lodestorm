class_name VrPointer
extends Node3D
## Points at menus with a VR controller, like the mouse (see docs/design/vr.md): while the local
## player uses a menu (a screen, a station, the pause panel), a beam comes out of the pointing
## hand, and where it points becomes a mouse cursor; the trigger clicks. The spot it points at is
## on a screen (`WorldPanel`, a station's card) or else on the plane facing the view through the
## menu's center (a station's parts), and the cursor is where that spot is seen from the view's
## camera (`ViewCamera`), so every menu takes it like the mouse without knowing about VR. The
## events go straight into the viewport (layout coordinates) from `VrGamepad.DEVICE`.
## Either trigger points with its hand and clicks; while pointing, both triggers are held back
## from the gamepad (`VrGamepad.mute`).
## It runs on while the game is paused.

## The hands' trackers and their triggers' actions.
const TRIGGERS: Dictionary[StringName, StringName] = {
	&"right_hand": &"right_trigger",
	&"left_hand": &"left_trigger",
}
## The trigger clicks from this far in, and lets go below the second value.
const PRESS_AT: float = 0.6
const RELEASE_AT: float = 0.4
## How far the beam reaches when it points at nothing, in m.
const BEAM_LENGTH: float = 4.0
const BEAM_WIDTH: float = 0.004
const DOT_RADIUS: float = 0.01
const COLOR := Color(1.0, 0.78, 0.4, 0.7)
## The cursor moves (an event) once it moved this far, in pixels.
const MOVE_STEP: float = 0.5

## The rig whose hands point (`VrRig.get_hand`).
var rig: VrRig
## The gamepad whose triggers it holds back while pointing.
var gamepad: VrGamepad
## The hand pointing (its tracker's name).
var hand: StringName = &"right_hand"

var _beam := MeshInstance3D.new()
var _dot := MeshInstance3D.new()
## Whether the trigger holds the mouse button down.
var _pressed: bool = false
## The cursor's last position (`Vector2.INF`: none).
var _cursor: Vector2 = Vector2.INF
## Whether each hand's trigger was in last frame (to switch hands on a press).
var _triggers_in: Dictionary[StringName, bool] = {}


func _init() -> void:
	name = "VrPointer"
	top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.disable_fog = true
	material.render_priority = Material.RENDER_PRIORITY_MAX - 1
	material.albedo_color = COLOR
	var box := BoxMesh.new()
	box.size = Vector3(BEAM_WIDTH, BEAM_WIDTH, 1.0)
	_beam.mesh = box
	_beam.material_override = material
	var sphere := SphereMesh.new()
	sphere.radius = DOT_RADIUS
	sphere.height = DOT_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	_dot.mesh = sphere
	_dot.material_override = material
	for mesh: MeshInstance3D in [_beam, _dot]:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visible = false
		add_child(mesh)


func _process(_delta: float) -> void:
	var menu: WorldMenu = _local_menu()
	var triggers: Dictionary[StringName, float] = _read_triggers()
	if menu:
		_switch_hand(triggers)
	var controller: XRController3D = rig.get_hand(hand) if rig else null
	var active: bool = menu != null and controller != null and controller.get_has_tracking_data()
	if gamepad:
		for action: StringName in TRIGGERS.values():
			gamepad.mute(action, active)
	if not active:
		_stop()
		return
	var camera: Camera3D = ViewCamera.of(self)
	var origin: Vector3 = controller.global_position
	var direction: Vector3 = -controller.global_basis.z.normalized()
	var spot: Vector3 = pointed_at(menu, origin, direction, camera)
	_show_beam(origin, direction, spot)
	if not spot.is_finite() or not camera or camera.is_position_behind(spot):
		return
	var cursor: Vector2 = camera.unproject_position(spot)
	var value: float = triggers.get(hand, 0.0)
	var pressed: bool = value >= (RELEASE_AT if _pressed else PRESS_AT)
	if not _cursor.is_finite() or cursor.distance_to(_cursor) >= MOVE_STEP:
		_move(cursor)
	if pressed != _pressed:
		_click(pressed)


func _exit_tree() -> void:
	_stop()


## Where a ray from `origin` along `direction` points at `menu`: on its screen (a `WorldPanel`, or
## a `Station`'s card while shown), else on the plane facing `camera` through the menu's center;
## `Vector3.INF` if it points away.
static func pointed_at(
	menu: WorldMenu, origin: Vector3, direction: Vector3, camera: Camera3D
) -> Vector3:
	var panels: Array[WorldPanel] = []
	if menu is WorldPanel:
		panels.append(menu as WorldPanel)
	var station := menu as Station
	if station and station.card and station.card.is_visible_in_tree():
		panels.append(station.card)
	for panel: WorldPanel in panels:
		if panel.pixel_at(origin, direction) != Vector2.INF:
			var hit: Variant = (
				Plane(panel.global_basis.z.normalized(), panel.global_position)
				. intersects_ray(origin, direction)
			)
			if hit != null:
				return hit
	if not camera:
		return Vector3.INF
	var facing := Plane(camera.global_basis.z.normalized(), menu.get_view_center())
	var on_plane: Variant = facing.intersects_ray(origin, direction)
	return on_plane if on_plane != null else Vector3.INF


## The menu the local player uses, or null.
func _local_menu() -> WorldMenu:
	for menu: WorldMenu in get_tree().get_nodes_in_group(WorldMenu.GROUP):
		if menu.user and menu.user.local:
			return menu
	return null


func _read_triggers() -> Dictionary[StringName, float]:
	var values: Dictionary[StringName, float] = {}
	for tracker_name: StringName in TRIGGERS:
		var tracker := XRServer.get_tracker(tracker_name) as XRControllerTracker
		var value: Variant = tracker.get_input(TRIGGERS[tracker_name]) if tracker else 0.0
		values[tracker_name] = value if value is float else 0.0
	return values


## A trigger pressed on the other hand makes that hand point (not while a click is held).
func _switch_hand(triggers: Dictionary[StringName, float]) -> void:
	for tracker_name: StringName in triggers:
		var now_in: bool = triggers[tracker_name] >= PRESS_AT
		var was_in: bool = _triggers_in.get(tracker_name, false)
		_triggers_in[tracker_name] = now_in
		if now_in and not was_in and tracker_name != hand and not _pressed:
			hand = tracker_name


func _show_beam(origin: Vector3, direction: Vector3, spot: Vector3) -> void:
	var length: float = origin.distance_to(spot) if spot.is_finite() else BEAM_LENGTH
	length = minf(length, BEAM_LENGTH * 4.0)
	var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD
	_beam.global_transform = Transform3D(
		Basis.looking_at(direction, up).scaled_local(Vector3(1.0, 1.0, length)),
		origin + direction * length * 0.5
	)
	_beam.visible = true
	_dot.visible = spot.is_finite()
	if _dot.visible:
		_dot.global_position = spot


func _move(cursor: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.device = VrGamepad.DEVICE
	motion.position = cursor
	motion.global_position = cursor
	motion.relative = cursor - _cursor if _cursor.is_finite() else Vector2.ZERO
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed else 0
	_cursor = cursor
	get_viewport().push_input(motion, true)


func _click(pressed: bool) -> void:
	_pressed = pressed
	var click := InputEventMouseButton.new()
	click.device = VrGamepad.DEVICE
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.position = _cursor
	click.global_position = _cursor
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(click, true)


## Hides the beam and lets go of the button.
func _stop() -> void:
	_beam.visible = false
	_dot.visible = false
	if _pressed and _cursor.is_finite() and is_inside_tree():
		_click(false)
	_pressed = false
	_cursor = Vector2.INF
