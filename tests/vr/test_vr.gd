extends GutTest
## The VR view: the controllers as a gamepad (`VrGamepad`, bound in the OpenXR action map) and the
## head on the desktop camera's line (`VrRig`). The headset itself isn't there in the tests.

const ACTION_MAP: OpenXRActionMap = preload("res://game/vr/openxr_action_map.tres")
const FRAME: String = "/interaction_profiles/valve/frame_controller_valve"
const RIG: PackedScene = preload("res://game/camera/iso_camera_rig.tscn")
const PANEL: PackedScene = preload("res://game/ui/world_panel.tscn")


## Every action the gamepad reads is in the action map and bound on the Steam Frame's controllers.
func test_frame_binds_every_gamepad_action() -> void:
	var names: Array[StringName] = []
	names.append_array(VrGamepad.BUTTONS.keys())
	names.append_array(VrGamepad.TRIGGERS.keys())
	names.append_array(VrGamepad.STICKS.keys())
	var profile: OpenXRInteractionProfile = ACTION_MAP.find_interaction_profile(FRAME)
	assert_not_null(profile, "no Steam Frame profile")
	var bound: Array[StringName] = []
	for binding: OpenXRIPBinding in profile.bindings:
		bound.append(StringName(binding.action.resource_name))
	for action_name: StringName in names:
		assert_true(_in_map(action_name), "%s isn't in the action map" % action_name)
		assert_has(bound, action_name, "%s isn't bound on the Steam Frame" % action_name)


## Every gamepad button and axis the input map uses can come from the VR controllers.
func test_gamepad_covers_the_input_map() -> void:
	var buttons: Array = VrGamepad.BUTTONS.values()
	var axes: Array = VrGamepad.TRIGGERS.values()
	for stick: JoyAxis in VrGamepad.STICKS.values():
		axes.append_array([stick, stick + 1])
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var button := event as InputEventJoypadButton
			if button:
				assert_has(buttons, button.button_index, "%s: button" % action)
			var motion := event as InputEventJoypadMotion
			if motion:
				assert_has(axes, motion.axis, "%s: axis" % action)


func test_buttons_and_sticks_press_actions() -> void:
	var gamepad: VrGamepad = add_child_autofree(VrGamepad.new())
	gamepad.set_process(false)
	gamepad.press(JOY_BUTTON_A, true)
	gamepad.move_axis(JOY_AXIS_LEFT_X, 1.0)
	gamepad.move_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await wait_process_frames(2)
	assert_true(Input.is_action_pressed(&"interact"), "A interacts")
	assert_true(Input.is_action_pressed(&"attack"), "the right trigger attacks")
	assert_almost_eq(Input.get_action_strength(&"move_right"), 1.0, 0.01, "the left stick walks")
	gamepad.release_all()
	await wait_process_frames(2)
	assert_false(Input.is_action_pressed(&"interact"), "released")
	assert_false(Input.is_action_pressed(&"attack"), "trigger released")
	assert_almost_eq(Input.get_action_strength(&"move_right"), 0.0, 0.01, "stick centered")


## The pointer lands on a screen where the ray hits it, else on the plane facing the view through
## the menu's center (a station's parts).
func test_pointer_lands_on_the_screen_or_the_menus_plane() -> void:
	var panel: WorldPanel = add_child_autofree(PANEL.instantiate())
	var camera: Camera3D = add_child_autofree(Camera3D.new())
	camera.position = Vector3(0.0, 0.0, 10.0)
	var on_screen: Vector3 = VrPointer.pointed_at(
		panel, Vector3(0.2, 0.1, 2.0), Vector3.FORWARD, camera
	)
	assert_almost_eq(on_screen, Vector3(0.2, 0.1, 0.0), Vector3.ONE * 0.001, "on the screen")
	var beside: Vector3 = VrPointer.pointed_at(
		panel, Vector3(5.0, 0.0, 2.0), Vector3.FORWARD, camera
	)
	assert_almost_eq(beside, Vector3(5.0, 0.0, 0.0), Vector3.ONE * 0.001, "on the menu's plane")
	var away: Vector3 = VrPointer.pointed_at(panel, Vector3(0.0, 0.0, 2.0), Vector3.BACK, camera)
	assert_false(away.is_finite(), "pointing away")


func test_head_floats_on_the_cameras_line() -> void:
	var forward := Vector3(1.0, -1.0, -1.0).normalized()
	var goal: Transform3D = VrRig.head_goal(Vector3(5.0, 0.0, 2.0), forward, 20.0)
	assert_almost_eq(goal.origin, Vector3(5.0, 0.0, 2.0) - forward * 20.0, Vector3.ONE * 0.001)
	var look: Vector3 = -goal.basis.z
	assert_almost_eq(look.y, 0.0, 0.001, "level: only the head tilts")
	assert_almost_eq(look, Vector3(1.0, 0.0, -1.0).normalized(), Vector3.ONE * 0.001)


## Without VR, the view's camera is the viewport's.
func test_view_camera_on_desktop() -> void:
	var node: Node3D = add_child_autofree(Node3D.new())
	assert_eq(ViewCamera.of(node), get_viewport().get_camera_3d())


## The head follows the desktop rig on its line; a far jump blinks (black, jump, clear again).
func test_head_follows_and_blinks_on_jumps() -> void:
	var target: Node3D = add_child_autofree(Node3D.new())
	var rig: IsoCameraRig = add_child_autofree(RIG.instantiate())
	rig.target = target
	var vr: VrRig = add_child_autofree(VrRig.new())
	await wait_process_frames(3)
	var line: Transform3D = VrRig.head_goal(
		rig.goal, rig.view_direction(), vr.settings.distance * rig.goal_zoom
	)
	assert_almost_eq(vr.global_position, line.origin, Vector3.ONE * 0.01, "on the line")
	assert_eq(ViewCamera.of(target), rig.get_camera(), "the layout keeps the desktop camera")
	target.global_position = Vector3(vr.settings.blink_distance * 3.0, 0.0, 0.0)
	await wait_process_frames(2)
	assert_gt(vr.blink, 0.0, "a far jump blinks")
	await wait_seconds(vr.settings.blink_time * 3.0)
	line = VrRig.head_goal(rig.goal, rig.view_direction(), vr.settings.distance * rig.goal_zoom)
	assert_almost_eq(vr.global_position, line.origin, Vector3.ONE * 0.5, "jumped there")
	assert_almost_eq(vr.blink, 0.0, 0.001, "clear again")


func _in_map(action_name: StringName) -> bool:
	for action_set: OpenXRActionSet in ACTION_MAP.action_sets:
		for action: OpenXRAction in action_set.actions:
			if StringName(action.resource_name) == action_name:
				return true
	return false
