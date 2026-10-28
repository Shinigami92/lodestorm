class_name PlayerInput
extends RefCounted
## What the `holder` is told to do: which of its `ACTIONS` are `held` or `just_pressed`, and where
## it walks (`move`). Only the local player reads the input devices, and none of it while it uses a
## 3D menu. A press still held when a menu opens or closes (`hold_back`), or one already used up
## (`use_up`, e.g. a hold that handed ammo), is ignored until it's released. Remote players (co-op,
## M7) and VR controllers are meant to feed the same calls.

## Actions that make the player act.
const ACTIONS: Array[StringName] = [
	&"attack", &"place_miner", &"interact", &"switch_weapon", &"reload", &"dash"
]

## The player acting on it.
var holder: Player

## Actions ignored until they're released.
var _held_back: Array[StringName] = []


## Forgets held-back actions once released; called every physics step before reading the input.
func update() -> void:
	_held_back.assign(_held_back.filter(Input.is_action_pressed))


## Whether `action` is held for the holder to act (not while it uses a menu, nor a held-back
## press).
func held(action: StringName) -> bool:
	return (
		holder.local
		and not holder.menu
		and action not in _held_back
		and Input.is_action_pressed(action)
	)


## Whether `action` was pressed this step for the holder to act (see `held`).
func just_pressed(action: StringName) -> bool:
	return held(action) and Input.is_action_just_pressed(action)


## Where it walks (x = right, y = back, as `Input.get_vector` gives it); zero while it doesn't
## act.
func move() -> Vector2:
	if not holder.local or holder.menu:
		return Vector2.ZERO
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


## Ignores every action held right now until it's released: the press that opened or closed a
## menu (e.g. a click) doesn't act again in the world.
func hold_back() -> void:
	_held_back.clear()
	for action: StringName in ACTIONS:
		if Input.is_action_pressed(action):
			_held_back.append(action)


## Ignores `action` until it's released (once per hold).
func use_up(action: StringName) -> void:
	_held_back.append(action)
