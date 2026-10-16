class_name WristDisplay
extends WorldMenu
## The suit's wrist display: `wrist` (J, the gamepad's View button) projects a holo card beside the
## player (a transparent `WorldPanel` with a `WristCard`), facing the camera; `wrist` again (or
## `pause`) puts it away. Like the other 3D menus, the camera moves in to frame the player and the
## card while it's open, so its text reads, and the player stands still meanwhile. Its first tab
## shows the cargo (the exact amounts behind the tubes on the back); the quest log comes as a second
## tab.

const CARD_SCENE: PackedScene = preload("res://game/player/wrist/wrist_card.tscn")
const PANEL_SCENE: PackedScene = preload("res://game/ui/world_panel.tscn")
## Where the card's bottom middle floats: beside the player (towards the camera's right), a little
## above the feet, so it never covers them.
const SIDE_OFFSET: float = 0.9
const HEIGHT: float = 0.35

## The player whose display it is.
var holder: Player

var _panel: WorldPanel
var _focus := Node3D.new()


func _ready() -> void:
	view_height = 2.6
	_panel = PANEL_SCENE.instantiate() as WorldPanel
	_panel.name = "Panel"
	_panel.size = Vector2(1.5, 1.6)
	_panel.pixels_per_meter = 450.0
	_panel.transparent = true
	_panel.menu = CARD_SCENE
	add_child(_panel)
	_panel.top_level = true
	_panel.visible = false
	_focus.name = "Focus"
	add_child(_focus)
	_focus.top_level = true
	view_focus = _focus
	if holder:
		holder.cargo_changed.connect(_on_cargo_changed)


func _input(event: InputEvent) -> void:
	if not holder:
		return
	if user and (event.is_action_pressed(&"wrist") or CLOSE_ACTIONS.any(event.is_action_pressed)):
		close()
		get_viewport().set_input_as_handled()
	elif (
		not user
		and event.is_action_pressed(&"wrist")
		and holder.menu == null
		and not holder.dead
		and open(holder)
	):
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if user and holder.dead:
		close()
	if user:
		_place()


## Whether the card shows.
func is_shown() -> bool:
	return user != null


## The card (for tests and probes).
func get_card() -> WristCard:
	return _panel.content as WristCard


func get_look_target() -> Vector3:
	return _panel.global_position


func _opened() -> void:
	_panel.visible = true
	_panel.set_on_top(true)
	_refresh()
	_place()


func _closed() -> void:
	_panel.visible = false
	_panel.set_on_top(false)


## Keeps the card beside the player, facing the camera (its bottom `HEIGHT` above the feet), and
## the camera's focus between the two.
func _place() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera or not holder:
		return
	var view: Basis = camera.global_basis.orthonormalized()
	var flat_right: Vector3 = Vector3(view.x.x, 0.0, view.x.z).normalized()
	var anchor: Vector3 = holder.global_position + Vector3.UP * HEIGHT
	anchor += flat_right * (SIDE_OFFSET + _panel.size.x * 0.5)
	var center: Vector3 = anchor + view.y * (_panel.size.y * 0.5)
	_panel.global_transform = Transform3D(view, center)
	_focus.global_position = holder.global_position.lerp(center, 0.5) + Vector3.UP * 0.3


func _refresh() -> void:
	var card := get_card()
	if card and holder:
		card.show_cargo(holder.cargo)


func _on_cargo_changed(_ore_type: OreType, _amount: float) -> void:
	if user:
		_refresh()
