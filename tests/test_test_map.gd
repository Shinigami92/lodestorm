extends GutTest

const TEST_MAP: PackedScene = preload("res://scenes/maps/test_map.tscn")

var _map: Node3D
var _player: Player
var _camera: Camera3D


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_camera = get_viewport().get_camera_3d()


func after_each() -> void:
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)


func test_camera_looks_at_player() -> void:
	assert_not_null(_camera)
	var to_player: Vector3 = (_player.global_position - _camera.global_position).normalized()
	assert_almost_eq(to_player.dot(-_camera.global_basis.z), 1.0, 0.001)


## "Right" means screen-right, whatever the camera's yaw.
func test_player_moves_relative_to_camera() -> void:
	var start: Vector3 = _player.global_position
	Input.action_press(&"move_right")
	await wait_physics_frames(20)
	var moved: Vector3 = _player.global_position - start
	moved.y = 0.0
	assert_gt(moved.length(), 0.5, "player didn't move")
	assert_almost_eq(moved.normalized().dot(_screen_right()), 1.0, 0.01)


func test_player_stands_on_ground() -> void:
	await wait_physics_frames(20)
	assert_true(_player.is_on_floor())
	assert_almost_eq(_player.global_position.y, 0.0, 0.05)


func test_right_stick_aims_and_turns_player() -> void:
	Input.action_press(&"aim_right")
	await wait_physics_frames(30)
	assert_almost_eq(_player.aim_direction.dot(_screen_right()), 1.0, 0.01)
	var facing: Vector3 = -_player.global_basis.z
	assert_almost_eq(facing.dot(_screen_right()), 1.0, 0.01)


func test_without_aim_input_player_faces_movement() -> void:
	Input.action_press(&"move_back")
	await wait_physics_frames(10)
	var screen_down: Vector3 = IsoInput.camera_relative(Vector2.DOWN, _camera.global_basis)
	assert_almost_eq(_player.aim_direction.dot(screen_down), 1.0, 0.01)


func test_mouse_aims_at_cursor_on_ground() -> void:
	var target: Vector3 = _player.global_position + Vector3(3.0, 0.0, 4.0)
	_player.aim_at_screen_position(_camera, _camera.unproject_position(target))
	assert_almost_eq(_player.aim_direction, Vector3(0.6, 0.0, 0.8), Vector3.ONE * 0.01)


func _screen_right() -> Vector3:
	return IsoInput.camera_relative(Vector2.RIGHT, _camera.global_basis)
