extends GutTest

const EPSILON: float = 0.001


func test_unrotated_camera_maps_forward_to_minus_z() -> void:
	var basis := Basis.from_euler(Vector3(deg_to_rad(-35.0), 0.0, 0.0))
	assert_almost_eq(IsoInput.camera_relative(Vector2.UP, basis), Vector3.FORWARD, _eps())
	assert_almost_eq(IsoInput.camera_relative(Vector2.RIGHT, basis), Vector3.RIGHT, _eps())


func test_yaw_rotates_directions() -> void:
	var basis := Basis.from_euler(Vector3(deg_to_rad(-35.0), deg_to_rad(45.0), 0.0))
	var forward: Vector3 = IsoInput.camera_relative(Vector2.UP, basis)
	assert_almost_eq(forward, Vector3(-1.0, 0.0, -1.0).normalized(), _eps())


## Pitch must not shorten forward movement compared to sideways movement.
func test_result_is_horizontal_and_unit_length() -> void:
	var basis := Basis.from_euler(Vector3(deg_to_rad(-60.0), deg_to_rad(30.0), 0.0))
	for input: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var direction: Vector3 = IsoInput.camera_relative(input, basis)
		assert_almost_eq(direction.y, 0.0, EPSILON)
		assert_almost_eq(direction.length(), 1.0, EPSILON)


func test_diagonal_is_not_faster() -> void:
	var direction: Vector3 = IsoInput.camera_relative(Vector2(1.0, -1.0), Basis.IDENTITY)
	assert_almost_eq(direction.length(), 1.0, EPSILON)


func test_no_input_means_no_direction() -> void:
	assert_eq(IsoInput.camera_relative(Vector2.ZERO, Basis.IDENTITY), Vector3.ZERO)


func _eps() -> Vector3:
	return Vector3.ONE * EPSILON
