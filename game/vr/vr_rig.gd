class_name VrRig
extends XROrigin3D
## The VR viewpoint (see docs/design/vr.md): the head floats on the desktop camera's line, at real
## scale, closer than the desktop camera (`VrSettings.distance` times the desktop rig's zoom), and
## turns freely; the view itself never turns. It glides after where the desktop rig is going
## (`IsoCameraRig.goal`), slower than the desktop camera; when that jumps (a station or a room
## framed, a respawn, a new scene) it blinks instead: fades to black, jumps and fades back in.
## A scene without a desktop rig (the boot screen) gets the head at its camera.
## The tracking space is centered on the head (`center`), so the origin is where the eyes are.
## It also draws the screen fades (`ScreenFade`: 2D, not in the headset) around the head.
## It runs on while the game is paused (the pause panel is framed too).

const GROUP: StringName = &"vr_rigs"
## The controllers' pose a hand follows: where it points (OpenXR action `aim_pose`).
const HAND_POSE: StringName = &"aim"
## Radius of the black sphere around the head for fades, in m.
const FADE_RADIUS: float = 0.2

@export var settings: VrSettings = preload("res://game/vr/vr_settings.tres")

## How black the blink is: 0 clear, 1 black.
var blink: float = 0.0

var _camera := XRCamera3D.new()
## The controllers by tracker name (`left_hand`, `right_hand`).
var _hands: Dictionary[StringName, XRController3D] = {}
var _fade := MeshInstance3D.new()
var _fade_material := StandardMaterial3D.new()
## The desktop rig it follows, or null.
var _rig: IsoCameraRig
## What the desktop rig framed last frame (`IsoCameraRig.framing`).
var _framing: Node3D
## Whether it's fading out to jump.
var _blinking: bool = false
## Whether the next frame jumps to the goal.
var _snap: bool = true
## The scene whose camera it takes without a desktop rig, and that camera.
var _scene: Node
var _scene_camera: Camera3D
## Seconds until it centers on the head (negative: not waiting).
var _center_in: float = -1.0


func _init() -> void:
	name = "VrRig"
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After the desktop rig, which decides where the view goes this frame.
	process_priority = 100
	# Moved in _process, after what it follows.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.name = "Head"
	add_child(_camera)
	for tracker: StringName in [&"left_hand", &"right_hand"] as Array[StringName]:
		var controller := XRController3D.new()
		controller.name = String(tracker).to_pascal_case()
		controller.tracker = tracker
		controller.pose = HAND_POSE
		add_child(controller)
		_hands[tracker] = controller
	_fade_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fade_material.no_depth_test = true
	_fade_material.disable_fog = true
	_fade_material.render_priority = Material.RENDER_PRIORITY_MAX
	_fade_material.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	var sphere := SphereMesh.new()
	sphere.radius = FADE_RADIUS
	sphere.height = FADE_RADIUS * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	_fade.name = "Fade"
	_fade.mesh = sphere
	_fade.material_override = _fade_material
	_fade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fade.visible = false
	_camera.add_child(_fade)


func _ready() -> void:
	_camera.current = true


func _process(delta: float) -> void:
	if get_viewport().get_camera_3d() != _camera:
		# A new scene's own camera took over.
		_camera.current = true
	_find_rig()
	var goal: Transform3D = _goal()
	if _jumps(goal) and not _blinking and not _snap:
		_blinking = true
	if _blinking:
		blink = move_toward(blink, 1.0, delta / settings.blink_time)
		if blink >= 1.0:
			_blinking = false
			_snap = true
	else:
		blink = move_toward(blink, 0.0, delta / settings.blink_time)
	if _snap:
		_snap = false
		global_transform = goal
	else:
		var weight: float = 1.0 - exp(-settings.follow_speed * delta)
		global_transform = Transform3D(goal.basis, global_position.lerp(goal.origin, weight))
	_show_fade()
	if _center_in >= 0.0:
		_center_in -= delta
		if _center_in < 0.0:
			center()


## Where the head goes for a camera at `focus` looking along `forward`: `distance` back along that
## line, facing the same way but level (the view never tilts, only the head does).
static func head_goal(focus: Vector3, forward: Vector3, distance: float) -> Transform3D:
	var flat := Vector3(forward.x, 0.0, forward.z)
	var turn: Basis = (
		Basis.looking_at(flat.normalized(), Vector3.UP) if flat.length() > 0.001 else Basis()
	)
	return Transform3D(turn, focus - forward.normalized() * distance)


## Centers the tracking space on the head: the eyes at the origin, looking where it faces (keeps
## the head's tilt). Seated or standing, the view starts at the same place.
func center() -> void:
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, false)


## Centers on the head after `VrSettings.center_delay` (the first poses of a session can be off).
func center_soon() -> void:
	_center_in = settings.center_delay


## The head's camera (the one drawn in VR).
func get_head() -> XRCamera3D:
	return _camera


## The controller of the hand with this tracker name (`left_hand`, `right_hand`), or null.
func get_hand(tracker: StringName) -> XRController3D:
	return _hands.get(tracker)


func _find_rig() -> void:
	var rig := get_tree().get_first_node_in_group(IsoCameraRig.GROUP) as IsoCameraRig
	if rig == _rig:
		return
	_rig = rig
	_snap = true
	if rig:
		_framing = rig.framing
		rig.snapped.connect(_on_rig_snapped)


func _goal() -> Transform3D:
	if _rig:
		return head_goal(_rig.goal, _rig.view_direction(), settings.distance * _rig.goal_zoom)
	var scene: Node = get_tree().current_scene
	if scene != _scene:
		_scene = scene
		_snap = true
		_scene_camera = null
		if scene:
			var cameras: Array[Node] = scene.find_children("*", "Camera3D")
			if not cameras.is_empty():
				_scene_camera = cameras[0] as Camera3D
	if is_instance_valid(_scene_camera):
		return head_goal(_scene_camera.global_position, -_scene_camera.global_basis.z, 0.0)
	return global_transform


## Whether the view jumps (blinks) rather than glides to `goal`: the desktop rig frames something
## else, or the goal is far.
func _jumps(goal: Transform3D) -> bool:
	var framing: Node3D = _rig.framing if _rig else null
	var changed: bool = framing != _framing
	_framing = framing
	return changed or global_position.distance_to(goal.origin) > settings.blink_distance


func _show_fade() -> void:
	var black: float = blink
	for fade: ScreenFade in get_tree().get_nodes_in_group(ScreenFade.GROUP):
		black = maxf(black, fade.opacity())
	_fade.visible = black > 0.001
	_fade_material.albedo_color.a = black


func _on_rig_snapped() -> void:
	_snap = true
