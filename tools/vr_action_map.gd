extends SceneTree
## Writes game/vr/openxr_action_map.tres: one action per gamepad element (VrGamepad reads them),
## bound per controller (see docs/technical/vr.md). Run, then tools/uids.sh:
##   "$GODOT4_EDITOR" --headless --path . -s tools/vr_action_map.gd

const HANDS := ["/user/hand/left", "/user/hand/right"]

## name, localized name, type
const ACTIONS := [
	["left_stick", "Left stick", 2],
	["right_stick", "Right stick", 2],
	["left_trigger", "Left trigger", 1],
	["right_trigger", "Right trigger", 1],
	["left_bumper", "Left bumper", 0],
	["right_bumper", "Right bumper", 0],
	["left_stick_click", "Left stick click", 0],
	["right_stick_click", "Right stick click", 0],
	["a", "A", 0],
	["b", "B", 0],
	["x", "X", 0],
	["y", "Y", 0],
	["dpad_up", "D-pad up", 0],
	["dpad_down", "D-pad down", 0],
	["dpad_left", "D-pad left", 0],
	["dpad_right", "D-pad right", 0],
	["view", "View", 0],
	["menu", "Menu", 0],
	["aim_pose", "Aim pose", 3],
	["haptic", "Haptic", 4],
]

const L := "/user/hand/left/"
const R := "/user/hand/right/"

## The shared part of every profile.
const COMMON := [
	["left_stick", L + "input/thumbstick"],
	["right_stick", R + "input/thumbstick"],
	["left_stick_click", L + "input/thumbstick/click"],
	["right_stick_click", R + "input/thumbstick/click"],
	["left_trigger", L + "input/trigger/value"],
	["right_trigger", R + "input/trigger/value"],
	["aim_pose", L + "input/aim/pose"],
	["aim_pose", R + "input/aim/pose"],
	["haptic", L + "output/haptic"],
	["haptic", R + "output/haptic"],
]

const PROFILES := {
	# Steam Frame: a gamepad split in two.
	"/interaction_profiles/valve/frame_controller_valve":
	[
		["left_bumper", L + "input/bumper/click"],
		["right_bumper", R + "input/bumper/click"],
		["a", R + "input/a/click"],
		["b", R + "input/b/click"],
		["x", R + "input/x/click"],
		["y", R + "input/y/click"],
		["dpad_up", L + "input/dpad_up/click"],
		["dpad_down", L + "input/dpad_down/click"],
		["dpad_left", L + "input/dpad_left/click"],
		["dpad_right", L + "input/dpad_right/click"],
		["view", L + "input/view/click"],
		["menu", R + "input/menu/click"],
	],
	# Quest Touch: grips as bumpers, X/Y on the left, no d-pad.
	"/interaction_profiles/oculus/touch_controller":
	[
		["left_bumper", L + "input/squeeze/value"],
		["right_bumper", R + "input/squeeze/value"],
		["a", R + "input/a/click"],
		["b", R + "input/b/click"],
		["x", L + "input/x/click"],
		["y", L + "input/y/click"],
		["menu", L + "input/menu/click"],
	],
	# Index: grips as bumpers, the left A/B as X/Y, pressing the left trackpad as the menu.
	"/interaction_profiles/valve/index_controller":
	[
		["left_bumper", L + "input/squeeze/value"],
		["right_bumper", R + "input/squeeze/value"],
		["a", R + "input/a/click"],
		["b", R + "input/b/click"],
		["x", L + "input/a/click"],
		["y", L + "input/b/click"],
		["menu", L + "input/trackpad/force"],
	],
}


func _init() -> void:
	var map := OpenXRActionMap.new()
	var action_set := OpenXRActionSet.new()
	action_set.resource_name = "lodestorm"
	action_set.localized_name = "Lodestorm"
	var actions := {}
	for entry: Array in ACTIONS:
		var action := OpenXRAction.new()
		action.resource_name = entry[0]
		action.localized_name = entry[1]
		action.action_type = entry[2] as OpenXRAction.ActionType
		action.toplevel_paths = PackedStringArray(HANDS)
		action_set.add_action(action)
		actions[entry[0]] = action
	map.add_action_set(action_set)
	for path: String in PROFILES:
		var profile := OpenXRInteractionProfile.new()
		profile.interaction_profile_path = path
		var bindings: Array = []
		for binding: Array in COMMON + (PROFILES[path] as Array):
			var ip := OpenXRIPBinding.new()
			ip.action = actions[binding[0]]
			ip.binding_path = binding[1]
			bindings.append(ip)
		profile.bindings = bindings
		map.add_interaction_profile(profile)
	var error := ResourceSaver.save(map, "res://game/vr/openxr_action_map.tres")
	print("saved: ", error_string(error))
	quit()
