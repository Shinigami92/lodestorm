class_name IsoInput
extends RefCounted
## Maps 2D stick/key input onto the ground plane as seen from the camera.


## Turns an input vector (x = right, y = back, as from `Input.get_vector`) into a horizontal
## world direction: "forward" is screen-up, "right" is screen-right. The camera's pitch is
## ignored, so a tilted camera doesn't slow down forward movement. Length stays at most 1.
static func camera_relative(input: Vector2, camera_basis: Basis) -> Vector3:
	var right := Vector3(camera_basis.x.x, 0.0, camera_basis.x.z).normalized()
	var forward := Vector3(-camera_basis.z.x, 0.0, -camera_basis.z.z).normalized()
	return (right * input.x - forward * input.y).limit_length(1.0)
