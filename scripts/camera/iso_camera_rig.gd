class_name IsoCameraRig
extends Node3D
## Desktop camera: looks down at the target from a fixed isometric angle and follows it; inside a
## `CameraZone`, it looks at the zone's focus instead.
## The VR diorama will be a separate rig; gameplay only uses the viewport's active camera.

@export var settings: IsoCameraSettings
@export var target: Node3D

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	# Moved in _process, so it follows the target's interpolated position instead.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	apply_settings()
	if target:
		global_position = target.global_position


func _process(delta: float) -> void:
	if not target:
		return
	var goal: Vector3 = target.get_global_transform_interpolated().origin
	var body := target as PhysicsBody3D
	var zone: CameraZone = CameraZone.containing(get_tree(), body) if body else null
	if zone:
		goal = zone.focus_position()
	global_position = global_position.lerp(goal, 1.0 - exp(-settings.follow_speed * delta))


func apply_settings() -> void:
	rotation = Vector3(-deg_to_rad(settings.pitch), deg_to_rad(settings.yaw), 0.0)
	_camera.position = Vector3(0.0, 0.0, settings.distance)
	if settings.orthographic:
		_camera.set_orthogonal(settings.size, _camera.near, _camera.far)
	else:
		_camera.set_perspective(settings.fov, _camera.near, _camera.far)
