extends GutTest

## Gameplay reads input actions only, so every action needs a binding per input device.
const KEYBOARD_MOUSE_AND_GAMEPAD: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_forward",
	&"move_back",
	&"shoot",
	&"interact",
	&"place_miner",
	&"pause",
]
## Mouse aiming uses the cursor position, so these only have gamepad bindings.
const GAMEPAD_ONLY: Array[StringName] = [
	&"aim_left",
	&"aim_right",
	&"aim_forward",
	&"aim_back",
]


func test_actions_have_keyboard_or_mouse_binding() -> void:
	for action: StringName in KEYBOARD_MOUSE_AND_GAMEPAD:
		assert_true(_has_event(action, false), "%s has no keyboard/mouse binding" % action)


func test_actions_have_gamepad_binding() -> void:
	for action: StringName in KEYBOARD_MOUSE_AND_GAMEPAD + GAMEPAD_ONLY:
		assert_true(_has_event(action, true), "%s has no gamepad binding" % action)


## Physical keycodes keep WASD in place on non-QWERTY layouts.
func test_keys_use_physical_keycodes() -> void:
	for action: StringName in KEYBOARD_MOUSE_AND_GAMEPAD:
		for event: InputEvent in _events(action):
			var key := event as InputEventKey
			if key:
				assert_ne(key.physical_keycode, KEY_NONE, "%s binds a logical key" % action)
				assert_eq(key.keycode, KEY_NONE, "%s binds a logical key" % action)


func _events(action: StringName) -> Array[InputEvent]:
	if not InputMap.has_action(action):
		return []
	return InputMap.action_get_events(action)


func _has_event(action: StringName, gamepad: bool) -> bool:
	for event: InputEvent in _events(action):
		var is_gamepad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_gamepad == gamepad:
			return true
	return false
