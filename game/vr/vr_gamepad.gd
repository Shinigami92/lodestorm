class_name VrGamepad
extends Node
## Turns the VR controllers into a gamepad: the Steam Frame's controllers are a gamepad split in
## two (sticks, triggers, bumpers, A/B/X/Y on the right, the d-pad on the left), so each OpenXR
## action (`game/vr/openxr_action_map.tres`, one per gamepad element) becomes the joypad events of
## its button or axis on a device of its own. Every action's gamepad binding in the input map and
## the menus' focus navigation work in VR unchanged. Other controllers are bound as close as they
## come (grips as bumpers, no d-pad on most).
## It runs on while the game is paused (the pause panel takes the gamepad too).

## The joypad device the events come from (one no real gamepad uses: Godot counts up from 0).
const DEVICE: int = 15
## The controllers' trackers.
const TRACKERS: Array[StringName] = [&"left_hand", &"right_hand"]
## OpenXR action (bool) → the gamepad button it presses.
const BUTTONS: Dictionary[StringName, JoyButton] = {
	&"a": JOY_BUTTON_A,
	&"b": JOY_BUTTON_B,
	&"x": JOY_BUTTON_X,
	&"y": JOY_BUTTON_Y,
	&"view": JOY_BUTTON_BACK,
	&"menu": JOY_BUTTON_START,
	&"left_stick_click": JOY_BUTTON_LEFT_STICK,
	&"right_stick_click": JOY_BUTTON_RIGHT_STICK,
	&"left_bumper": JOY_BUTTON_LEFT_SHOULDER,
	&"right_bumper": JOY_BUTTON_RIGHT_SHOULDER,
	&"dpad_up": JOY_BUTTON_DPAD_UP,
	&"dpad_down": JOY_BUTTON_DPAD_DOWN,
	&"dpad_left": JOY_BUTTON_DPAD_LEFT,
	&"dpad_right": JOY_BUTTON_DPAD_RIGHT,
}
## OpenXR action (float) → the gamepad trigger axis it moves.
const TRIGGERS: Dictionary[StringName, JoyAxis] = {
	&"left_trigger": JOY_AXIS_TRIGGER_LEFT,
	&"right_trigger": JOY_AXIS_TRIGGER_RIGHT,
}
## OpenXR action (vector2) → the gamepad stick's x axis (its y axis is the next one).
const STICKS: Dictionary[StringName, JoyAxis] = {
	&"left_stick": JOY_AXIS_LEFT_X,
	&"right_stick": JOY_AXIS_RIGHT_X,
}
## An axis sends an event once it moved this far (or reached 0).
const AXIS_STEP: float = 0.01
## A float action counts as a press from this value on (grips bound as bumpers).
const PRESS_THRESHOLD: float = 0.5

## Actions held back (read as released), e.g. the triggers while they click on a menu (`VrPointer`).
var _muted: Dictionary[StringName, bool] = {}
## Buttons pressed and axes' values, as last sent.
var _buttons: Dictionary[JoyButton, bool] = {}
var _axes: Dictionary[JoyAxis, float] = {}


func _init() -> void:
	name = "VrGamepad"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	var trackers: Array[XRControllerTracker] = []
	for tracker_name: StringName in TRACKERS:
		var tracker := XRServer.get_tracker(tracker_name) as XRControllerTracker
		if tracker:
			trackers.append(tracker)
	for action: StringName in BUTTONS:
		var pressed: bool = false
		for tracker: XRControllerTracker in trackers:
			pressed = pressed or _pressed(tracker.get_input(action))
		press(BUTTONS[action], pressed)
	for action: StringName in TRIGGERS:
		var value: float = 0.0
		for tracker: XRControllerTracker in trackers:
			if not _muted.get(action, false):
				value = maxf(value, _float(tracker.get_input(action)))
		move_axis(TRIGGERS[action], value)
	for action: StringName in STICKS:
		var stick := Vector2.ZERO
		for tracker: XRControllerTracker in trackers:
			var value: Variant = tracker.get_input(action)
			if value is Vector2 and (value as Vector2).length() > stick.length():
				stick = value
		# OpenXR's y points up, a gamepad's down.
		move_axis(STICKS[action], stick.x)
		move_axis((STICKS[action] + 1) as JoyAxis, -stick.y)


func _exit_tree() -> void:
	release_all()


## Holds `action` back (it reads as released) or lets it through again.
func mute(action: StringName, muted: bool) -> void:
	_muted[action] = muted


## Presses or releases a gamepad button (an event only on a change).
func press(button: JoyButton, pressed: bool) -> void:
	if _buttons.get(button, false) == pressed:
		return
	_buttons[button] = pressed
	var event := InputEventJoypadButton.new()
	event.device = DEVICE
	event.button_index = button
	event.pressed = pressed
	event.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


## Moves a gamepad axis to `value` (an event once it moved `AXIS_STEP`, or reached 0).
func move_axis(axis: JoyAxis, value: float) -> void:
	var last: float = _axes.get(axis, 0.0)
	if absf(value - last) < AXIS_STEP and not (value == 0.0 and last != 0.0):
		return
	_axes[axis] = value
	var event := InputEventJoypadMotion.new()
	event.device = DEVICE
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


## Releases every button and centers every axis (e.g. when it stops).
func release_all() -> void:
	for button: JoyButton in _buttons.keys():
		press(button, false)
	for axis: JoyAxis in _axes.keys():
		move_axis(axis, 0.0)


static func _pressed(value: Variant) -> bool:
	if value is bool:
		return value
	return _float(value) >= PRESS_THRESHOLD


static func _float(value: Variant) -> float:
	if value is float:
		return value
	if value is bool:
		return 1.0 if value else 0.0
	return 0.0
