extends GutTest
## The terrain's cut-away: the camera rig aims it at its target, it presses down the ground between
## the camera and the target (above the target's feet), and the scatter on the rock hides there.

const RIG: PackedScene = preload("res://game/camera/iso_camera_rig.tscn")
## A target standing at the origin, seen by a camera up and back.
const AIM := Vector4(0.0, 1.2, 0.0, 7.0)
const CAMERA := Vector3(0.0, 24.0, 30.0)


func after_each() -> void:
	IsoCameraRig.cutaway_target = Vector4.ZERO
	IsoCameraRig.cutaway_camera = Vector3.ZERO


func test_rig_aims_the_cutaway_at_its_target() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	target.global_position = Vector3(10.0, 2.0, 5.0)
	var rig := RIG.instantiate() as IsoCameraRig
	rig.target = target
	add_child_autofree(rig)
	await wait_process_frames(2)
	var aim: Vector4 = IsoCameraRig.cutaway_target
	var settings: IsoCameraSettings = rig.settings
	assert_almost_eq(
		Vector3(aim.x, aim.y, aim.z),
		Vector3(10.0, 2.0 + settings.cutaway_height, 5.0),
		Vector3.ONE * 0.01
	)
	assert_eq(aim.w, settings.cutaway_radius)
	assert_almost_eq(
		IsoCameraRig.cutaway_camera,
		(rig.get_node("Camera3D") as Camera3D).global_position,
		Vector3.ONE * 0.01
	)
	rig.target = null
	await wait_process_frames(1)
	assert_eq(IsoCameraRig.cutaway_target.w, 0.0, "off without a target")


## Ground between the camera and the target is pressed down; behind the target, beside the line,
## and the ground the target stands on stay.
func test_presses_the_ground_between_camera_and_target() -> void:
	IsoCameraRig.cutaway_target = AIM
	IsoCameraRig.cutaway_camera = CAMERA
	var on_line: Vector3 = Vector3(AIM.x, AIM.y, AIM.z).lerp(CAMERA, 0.3)
	assert_almost_eq(IsoCameraRig.cutaway_press(on_line), 1.0, 0.01, "a cliff in between")
	assert_eq(IsoCameraRig.cutaway_press(Vector3(0.0, 8.0, -10.0)), 0.0, "behind the target")
	assert_eq(IsoCameraRig.cutaway_press(on_line + Vector3(12.0, 0.0, 0.0)), 0.0, "beside it")
	assert_eq(IsoCameraRig.cutaway_press(Vector3(0.0, 0.0, 3.0)), 0.0, "the ground at the feet")
	IsoCameraRig.cutaway_target.w = 0.0
	assert_eq(IsoCameraRig.cutaway_press(on_line), 0.0, "off")


func test_scatter_on_the_rock_hides_in_the_cutaway() -> void:
	var cutaway := ScatterCutaway.new()
	add_child_autofree(cutaway)
	var inside := Transform3D(Basis(), Vector3(AIM.x, AIM.y, AIM.z).lerp(CAMERA, 0.3))
	var outside := Transform3D(Basis(), Vector3(20.0, 8.0, 0.0))
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.instance_count = 2
	mesh.set_instance_transform(0, inside)
	mesh.set_instance_transform(1, outside)
	cutaway.watch(mesh, [inside, outside])
	IsoCameraRig.cutaway_target = AIM
	IsoCameraRig.cutaway_camera = CAMERA
	await wait_process_frames(2)
	# (The headless renderer doesn't keep instance transforms, so this asks the cut-away.)
	assert_true(cutaway.is_hidden(mesh, 0))
	assert_false(cutaway.is_hidden(mesh, 1))
	assert_eq(cutaway.hidden_count(), 1)
	IsoCameraRig.cutaway_target.w = 0.0
	await wait_process_frames(2)
	assert_eq(cutaway.hidden_count(), 0, "shown again")
