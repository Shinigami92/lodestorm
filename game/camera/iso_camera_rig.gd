class_name IsoCameraRig
extends Node3D
## Desktop camera: looks down at the target from a fixed isometric angle and follows it; inside a
## `CameraZone`, it looks at the zone's focus instead. While the target uses a 3D menu (a
## `WorldMenu`: a screen or a station), it moves in to frame it, keeping the angle.
## The VR diorama will be a separate rig; gameplay only uses the viewport's active camera.
## `shake` jiggles the view (e.g. the ship's hull in the clouds).
## It also aims the terrain's cut-away at the target (the shader globals `cutaway_target` and
## `cutaway_camera`, see `assets/shaders/terrain.gdshader`), so a cliff between the camera and the
## player doesn't hide them.

const GROUP: StringName = &"camera_rigs"
## Where the pressed-down ground ends, below where the cut-away aims, and how far above that the
## ground is pressed down fully, in m (the same as in the terrain shader).
const CUTAWAY_FLOOR_BELOW: float = 0.8
const CUTAWAY_FULL_ABOVE: float = 2.0

## The terrain's cut-away right now (what the shader globals hold): where it aims (xyz) and its
## radius (w, 0: off), and the camera it's for.
static var cutaway_target: Vector4 = Vector4.ZERO
static var cutaway_camera: Vector3 = Vector3.ZERO

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
		_aim_cutaway(Vector3.ZERO, 0.0)
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
	var weight: float = 1.0 - exp(-settings.follow_speed * delta)
	global_position = global_position.lerp(goal, weight)
	if zoom != goal_zoom:
		zoom = lerpf(zoom, goal_zoom, weight)
		if absf(zoom - goal_zoom) < 0.001:
			zoom = goal_zoom
		apply_settings()
	var aim: Vector3 = target.get_global_transform_interpolated().origin
	_aim_cutaway(aim + Vector3.UP * settings.cutaway_height, settings.cutaway_radius)


func _exit_tree() -> void:
	_aim_cutaway(Vector3.ZERO, 0.0)


func apply_settings() -> void:
	rotation = Vector3(-deg_to_rad(settings.pitch), deg_to_rad(settings.yaw), 0.0)
	if settings.orthographic:
		_camera.position = Vector3(0.0, 0.0, settings.distance)
		_camera.set_orthogonal(settings.size * zoom, _camera.near, _camera.far)
	else:
		_camera.position = Vector3(0.0, 0.0, settings.distance * zoom)
		_camera.set_perspective(settings.fov, _camera.near, _camera.far)


## How far the terrain shader presses the ground at global `point` down right now: 0 not at all,
## 1 to just above the target's feet (things standing there would float, see `ScatterCutaway`).
static func cutaway_press(point: Vector3) -> float:
	var radius: float = cutaway_target.w
	if radius <= 0.0:
		return 0.0
	var aim := Vector3(cutaway_target.x, cutaway_target.y, cutaway_target.z)
	var to_eye: Vector3 = cutaway_camera - aim
	var along: float = (point - aim).dot(to_eye) / to_eye.length_squared()
	if along <= 0.0:
		return 0.0
	var off_line: float = point.distance_to(aim + to_eye * minf(along, 1.0))
	var floor_level: float = aim.y - CUTAWAY_FLOOR_BELOW
	return (
		(1.0 - smoothstep(radius * 0.6, radius, off_line))
		* smoothstep(floor_level + 0.5, floor_level + CUTAWAY_FULL_ABOVE, point.y)
	)


## Points the terrain's cut-away at `at` with `radius` (0: off), seen from this rig's camera.
func _aim_cutaway(at: Vector3, radius: float) -> void:
	cutaway_target = Vector4(at.x, at.y, at.z, radius)
	if _camera.is_inside_tree():
		cutaway_camera = _camera.global_position
	RenderingServer.global_shader_parameter_set(&"cutaway_target", cutaway_target)
	RenderingServer.global_shader_parameter_set(&"cutaway_camera", cutaway_camera)


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
