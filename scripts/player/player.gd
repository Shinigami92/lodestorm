class_name Player
extends CharacterBody3D
## Twin-stick player: moves relative to the camera and faces the aim direction. Aims at the
## mouse cursor on the ground, with the right stick, or else in the movement direction.

## Ignore cursor positions this close to the player, the direction flips around too easily.
const MIN_MOUSE_AIM_DISTANCE: float = 0.1

@export var settings: PlayerSettings

## Horizontal unit vector the player faces (and will shoot in).
var aim_direction: Vector3 = Vector3.FORWARD

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Whether the mouse was used for aiming more recently than the right stick.
var _aim_with_mouse: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_aim_with_mouse = true


func _physics_process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var camera_basis: Basis = camera.global_basis if camera else Basis.IDENTITY

	var move_input: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back"
	)
	var move: Vector3 = IsoInput.camera_relative(move_input, camera_basis)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(
		move * settings.move_speed, settings.acceleration * delta
	)
	velocity = Vector3(horizontal.x, velocity.y, horizontal.z)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()

	_update_aim(camera, camera_basis, move)
	var target_yaw: float = atan2(-aim_direction.x, -aim_direction.z)
	var yaw: float = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-settings.turn_speed * delta))
	# A fresh basis instead of setting rotation.y keeps the scale from drifting over time.
	basis = Basis(Vector3.UP, yaw)


func _update_aim(camera: Camera3D, camera_basis: Basis, move: Vector3) -> void:
	var stick: Vector2 = Input.get_vector(&"aim_left", &"aim_right", &"aim_forward", &"aim_back")
	if stick != Vector2.ZERO:
		_aim_with_mouse = false
		aim_direction = IsoInput.camera_relative(stick, camera_basis).normalized()
	elif _aim_with_mouse and camera:
		aim_at_screen_position(camera, get_viewport().get_mouse_position())
	elif move != Vector3.ZERO:
		aim_direction = move.normalized()


## Aims at the point on the ground (at the player's height) under the given screen position.
func aim_at_screen_position(camera: Camera3D, screen_position: Vector2) -> void:
	var ground := Plane(Vector3.UP, global_position.y)
	var hit: Variant = ground.intersects_ray(
		camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position)
	)
	if hit == null:
		return
	var to_cursor: Vector3 = (hit as Vector3) - global_position
	to_cursor.y = 0.0
	if to_cursor.length() > MIN_MOUSE_AIM_DISTANCE:
		aim_direction = to_cursor.normalized()
