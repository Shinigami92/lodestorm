class_name Terminal
extends Interactable
## A console with a screen (`Head/Panel`, a `WorldPanel`) showing `menu`. Using it opens the menu
## for that player; nobody else can use it meanwhile. The screen leans back to face the isometric
## camera, so it reads without distortion.

## The menu on the screen.
@export var menu: PackedScene
## How much the camera of the player using it sees (visible height in m); 0: the screen's
## default (`WorldPanel.view_height`).
@export var view_height: float = 0.0
## What that camera centers on; the screen when not set.
@export var view_focus: Node3D

@onready var panel: WorldPanel = $Head/Panel


func _init() -> void:
	used.connect(_on_used)


func _ready() -> void:
	panel.menu = menu
	if view_height > 0.0:
		panel.view_height = view_height
	panel.view_focus = view_focus
	super()
	panel.opened.connect(_on_panel_changed.unbind(1))
	panel.closed.connect(_on_panel_changed.unbind(1))


func _on_used(player: Player) -> void:
	panel.open(player)


func _on_panel_changed() -> void:
	enabled = panel.user == null
