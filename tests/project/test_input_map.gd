extends GutTest

## Gameplay reads input actions only, so every action needs a binding per input device.
const KEYBOARD_MOUSE_AND_GAMEPAD: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_forward",
	&"move_back",
	&"attack",
	&"interact",
	&"place_miner",
	&"miner_prev",
	&"miner_next",
	&"switch_weapon",
	&"reload",
	&"pause",
]
## Developer tools, only on the keyboard.
const KEYBOARD_ONLY: Array[StringName] = [&"debug_overlay"]
## Mouse aiming uses the cursor position, so these only have gamepad bindings.
const GAMEPAD_ONLY: Array[StringName] = [
	&"aim_left",
	&"aim_right",
	&"aim_forward",
	&"aim_back",
]


func test_actions_have_keyboard_or_mouse_binding() -> void:
	for action: StringName in KEYBOARD_MOUSE_AND_GAMEPAD + KEYBOARD_ONLY:
		assert_true(_has_event(action, false), "%s has no keyboard/mouse binding" % action)


func test_actions_have_gamepad_binding() -> void:
	for action: StringName in KEYBOARD_MOUSE_AND_GAMEPAD + GAMEPAD_ONLY:
		assert_true(_has_event(action, true), "%s has no gamepad binding" % action)


## Physical keycodes keep WASD in place on non-QWERTY layouts.
func test_keys_use_physical_keycodes() -> void:
	for action: StringName in KEYBOARD_MOUSE_AND_GAMEPAD + KEYBOARD_ONLY:
		for event: InputEvent in _events(action):
			var key := event as InputEventKey
			if key:
				assert_ne(key.physical_keycode, KEY_NONE, "%s binds a logical key" % action)
				assert_eq(key.keycode, KEY_NONE, "%s binds a logical key" % action)


## Device -1 means every keyboard/gamepad, so a second gamepad (co-op) works too.
func test_bindings_apply_to_all_devices() -> void:
	for action: StringName in KEYBOARD_MOUSE_AND_GAMEPAD + GAMEPAD_ONLY:
		for event: InputEvent in _events(action):
			assert_eq(event.device, -1, "%s binds a single device" % action)


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
