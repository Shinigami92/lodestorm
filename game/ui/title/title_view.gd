class_name TitleView
extends WorldMenu
## The title view the game opens on, instead of a main menu (see GAME_DESIGN.md, UI): the ship
## drifting in space with its outside showing (`Ship.show_outside`), the game's name as a hologram
## beside it and "Press any button" below. Any button (a key, a mouse or gamepad button) ends it:
## the camera glides into the ship to the player in cabin 1. Meanwhile the view drifts slowly
## around the ship (`drift`) and the ship's countdown hides. After `credits_delay` s without input,
## the credits scroll beside the name instead of the prompt; any input brings the prompt back.
## It's a menu the first player uses from the start, so they stand still meanwhile. It turns to
## face the camera, so its children are laid out on the screen's plane.

## Whether the game opens on it (off in the tests and probes).
static var shows: bool = true

## The ship it shows from outside.
@export var ship: Ship
## Seconds without input before the credits show. TBD (playtest).
@export var credits_delay: float = 30.0
## How fast the credits scroll, in their pixels per s. TBD (playtest).
@export var credits_speed: float = 30.0

## How far the view drifts around its focus, in m, and how long one round takes, in s.
@export var drift: float = 1.5
@export var drift_period: float = 40.0

## Seconds since the last input.
var idle_time: float = 0.0

var _drift_time: float = 0.0

@onready var _prompt: Label3D = $Prompt
@onready var _focus: Node3D = $Focus
@onready var _focus_rest: Vector3 = _focus.position
@onready var _credits: WorldPanel = $Credits


func _ready() -> void:
	# In front of the ship.
	_credits.set_on_top(true)
	_show_credits(false)
	if shows:
		_start.call_deferred()
	else:
		visible = false
		set_process(false)
		set_process_input(false)


func _process(delta: float) -> void:
	if not user:
		return
	idle_time += delta
	_drift_time += delta
	var angle: float = TAU * _drift_time / drift_period
	_focus.position = _focus_rest + Vector3(sin(angle), 0.5 * sin(2.0 * angle), 0.0) * drift
	if idle_time >= credits_delay and not _credits.visible:
		_show_credits(true)


func _input(event: InputEvent) -> void:
	if not user:
		return
	idle_time = 0.0
	if not is_button(event):
		return
	get_viewport().set_input_as_handled()
	if _credits.visible:
		_show_credits(false)
	else:
		close()


## Whether `event` is a button pressed: a key, a mouse or a gamepad button (not moving the mouse
## or a stick).
static func is_button(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	return (
		event is InputEventKey
		or event is InputEventMouseButton
		or event is InputEventJoypadButton
		or event is InputEventAction
	)


## Whether the credits show (instead of the prompt).
func credits_shown() -> bool:
	return _credits.visible


func _opened() -> void:
	visible = true
	idle_time = 0.0
	if ship:
		ship.show_outside = true
		ship.countdown_hidden = true
	var rig := get_tree().get_first_node_in_group(IsoCameraRig.GROUP) as IsoCameraRig
	if rig:
		# Its children are laid out on the screen's plane: x right, y up.
		global_basis = rig.global_basis.orthonormalized()
		rig.snap()


func _closed() -> void:
	visible = false
	_show_credits(false)
	if ship:
		ship.show_outside = false
		ship.countdown_hidden = false


func _start() -> void:
	var player: Player = Station.nth_player(get_tree(), 1)
	if player:
		open(player)


func _show_credits(shown: bool) -> void:
	_credits.visible = shown
	_prompt.visible = not shown
	var credits := _credits.content as Credits
	if credits:
		credits.restart()
		credits.scroll_speed = credits_speed if shown else 0.0
	if not shown:
		idle_time = 0.0
