class_name IsoCameraRig
extends Node3D
## Desktop camera: looks down at the target from a fixed isometric angle and follows it; inside a
## `CameraZone`, it looks at the zone's focus instead. While the target uses a 3D menu (a
## `WorldMenu`: a screen or a station), it moves in to frame it, keeping the angle.
## The VR diorama will be a separate rig; gameplay only uses the viewport's active camera.
## `shake` jiggles the view (e.g. the ship's hull in the clouds), and so do tremors (`tremble`: a
## huge alien's steps); scaled with the zoom, so a framed menu shakes no more than the whole view
## and stays readable.
## It runs on while the game is paused, so it can frame the pause panel (still, without shaking).

const GROUP: StringName = &"camera_rigs"

@export var settings: IsoCameraSettings
@export var target: Node3D

## How close the camera is: 1 normally, smaller while it frames a menu.
var zoom: float = 1.0
## How far the view shakes at zoom 1, in m (0: still).
var shake: float = 0.0

var _shake_time: float = 0.0
## The strongest tremor of this frame and of the one before (m): the sources may run before or
## after the rig.
var _tremor: float = 0.0
var _tremor_next: float = 0.0
## Whether the next frame jumps to the goal instead of gliding there.
var _snap: bool = false

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Moved in _process, so it follows the target's interpolated position instead.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	apply_settings()
	if target:
		global_position = target.global_position


func _process(delta: float) -> void:
	_shake(delta)
	if not target:
		return
	var goal: Vector3 = target.get_global_transform_interpolated().origin
	var goal_zoom: float = 1.0
	var body := target as PhysicsBody3D
	var zone: CameraZone = CameraZone.containing(get_tree(), body) if body else null
	if zone:
		goal = zone.focus_position()
	var menu: WorldMenu = WorldMenu.used_by(get_tree(), target)
	if menu:
		goal = menu.get_view_center()
		goal_zoom = menu.view_height / view_height()
	var weight: float = 1.0 if _snap else 1.0 - exp(-settings.follow_speed * delta)
	_snap = false
	global_position = global_position.lerp(goal, weight)
	if zoom != goal_zoom:
		zoom = lerpf(zoom, goal_zoom, weight)
		if absf(zoom - goal_zoom) < 0.001:
			zoom = goal_zoom
		apply_settings()


## Jumps to where it's going next frame instead of gliding there (e.g. the title view at the start).
func snap() -> void:
	_snap = true


func apply_settings() -> void:
	rotation = Vector3(-deg_to_rad(settings.pitch), deg_to_rad(settings.yaw), 0.0)
	if settings.orthographic:
		_camera.position = Vector3(0.0, 0.0, settings.distance)
		_camera.set_orthogonal(settings.size * zoom, _camera.near, _camera.far)
	else:
		_camera.position = Vector3(0.0, 0.0, settings.distance * zoom)
		_camera.set_perspective(settings.fov, _camera.near, _camera.far)


## Shakes the view by `amount` (m at zoom 1) this frame on top of `shake`; the strongest tremor
## of a frame counts.
func tremble(amount: float) -> void:
	_tremor_next = maxf(_tremor_next, amount)


func _shake(delta: float) -> void:
	_shake_time += delta
	_tremor = _tremor_next
	_tremor_next = 0.0
	var t: float = _shake_time
	var amount: float = 0.0 if get_tree().paused else (shake + _tremor) * zoom
	_camera.h_offset = amount * (sin(t * 37.0) + 0.6 * sin(t * 23.0 + 1.3)) / 1.6
	_camera.v_offset = amount * (sin(t * 29.0 + 0.7) + 0.6 * sin(t * 41.0)) / 1.6


## Where the camera looks (its forward direction, global).
func view_direction() -> Vector3:
	return -global_basis.z


## How much the camera sees at its target without zoom (visible height in m).
func view_height() -> float:
	if settings.orthographic:
		return settings.size
	return 2.0 * settings.distance * tan(deg_to_rad(settings.fov) * 0.5)
