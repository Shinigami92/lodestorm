@abstract class_name WorldMenu
extends Node3D
## Something in the world a player uses as a menu (there's no 2D HUD): a screen (`WorldPanel`) or
## an object with selectable parts (`Station`). One player uses it at a time (`open`). Meanwhile
## that player doesn't move or act, their camera moves in to frame it (`view_height`, centered on
## `view_focus` if set), and it takes their input until it closes (`close`, also with `pause` or
## `ui_cancel`).

## Emitted when a player starts using it.
signal opened(player: Player)
## Emitted when the player using it is done.
signal closed(player: Player)

const GROUP: StringName = &"world_menus"
## Actions that close it.
const CLOSE_ACTIONS: Array[StringName] = [&"pause", &"ui_cancel"]

## How much the camera of the player using it sees (visible height in m): it frames the menu with
## some room around it. TBD (playtest).
@export var view_height: float = 1.6
## What the camera of the player using it centers on; the menu itself when not set.
@export var view_focus: Node3D

## The player using it, or null.
var user: Player


func _init() -> void:
	add_to_group(GROUP)


## Starts `player` using it, unless someone else does already. Returns whether it opened.
func open(player: Player) -> bool:
	if user:
		return user == player
	user = player
	player.menu = self
	_opened()
	opened.emit(player)
	return true


## Ends using it.
func close() -> void:
	if not user:
		return
	var player: Player = user
	user = null
	if is_instance_valid(player) and player.menu == self:
		player.menu = null
	_closed()
	closed.emit(player)


## Where the camera of the player using it centers.
func get_view_center() -> Vector3:
	return view_focus.global_position if view_focus else global_position


## Where the player using it looks.
func get_look_target() -> Vector3:
	return global_position


## Called when a player starts using it.
func _opened() -> void:
	pass


## Called when the player using it is done.
func _closed() -> void:
	pass


## The menu `player` is using, or null.
static func used_by(tree: SceneTree, player: Node) -> WorldMenu:
	if not player:
		return null
	for menu: WorldMenu in tree.get_nodes_in_group(GROUP):
		if menu.user == player:
			return menu
	return null
