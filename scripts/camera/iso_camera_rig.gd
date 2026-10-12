class_name IsoCameraRig
extends Node3D
## Desktop camera: looks down at the target from a fixed isometric angle and follows it; inside a
## `CameraZone`, it looks at the zone's focus instead. While the target uses a 3D menu (a
## `WorldPanel`), it moves in to frame the menu's screen, keeping the angle.
## The VR diorama will be a separate rig; gameplay only uses the viewport's active camera.
## `shake` jiggles the view (e.g. the ship's hull in the clouds).

const GROUP: StringName = &"camera_rigs"

@export var settings: IsoCameraSettings
@export var target: Node3D

## How close the camera is: 1 normally, smaller while it frames a menu.
var zoom: float = 1.0
## How far the view shakes, in m (0: still).
var shake: float = 0.0

var _shake_time: float = 0.0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	add_to_group(GROUP)
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
	var panel: WorldPanel = WorldPanel.used_by(get_tree(), target)
	if panel:
		goal = panel.get_view_center()
		goal_zoom = panel.view_height / view_height()
	var weight: float = 1.0 - exp(-settings.follow_speed * delta)
	global_position = global_position.lerp(goal, weight)
	if zoom != goal_zoom:
		zoom = lerpf(zoom, goal_zoom, weight)
		if absf(zoom - goal_zoom) < 0.001:
			zoom = goal_zoom
		apply_settings()


func apply_settings() -> void:
	rotation = Vector3(-deg_to_rad(settings.pitch), deg_to_rad(settings.yaw), 0.0)
	if settings.orthographic:
		_camera.position = Vector3(0.0, 0.0, settings.distance)
		_camera.set_orthogonal(settings.size * zoom, _camera.near, _camera.far)
	else:
		_camera.position = Vector3(0.0, 0.0, settings.distance * zoom)
		_camera.set_perspective(settings.fov, _camera.near, _camera.far)


func _shake(delta: float) -> void:
	_shake_time += delta
	var t: float = _shake_time
	_camera.h_offset = shake * (sin(t * 37.0) + 0.6 * sin(t * 23.0 + 1.3)) / 1.6
	_camera.v_offset = shake * (sin(t * 29.0 + 0.7) + 0.6 * sin(t * 41.0)) / 1.6


## How much the camera sees at its target without zoom (visible height in m).
func view_height() -> float:
	if settings.orthographic:
		return settings.size
	return 2.0 * settings.distance * tan(deg_to_rad(settings.fov) * 0.5)
