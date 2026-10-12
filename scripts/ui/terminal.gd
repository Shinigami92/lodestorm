class_name Terminal
extends Interactable
## A console with a screen (`Head/Panel`, a `WorldPanel`) showing `menu`. Using it opens the menu
## for that player; nobody else can use it meanwhile. The screen leans back to face the isometric
## camera, so it reads without distortion.

## The menu on the screen.
@export var menu: PackedScene

@onready var panel: WorldPanel = $Head/Panel


func _init() -> void:
	used.connect(_on_used)


func _ready() -> void:
	panel.menu = menu
	super()
	panel.opened.connect(_on_panel_changed.unbind(1))
	panel.closed.connect(_on_panel_changed.unbind(1))


func _on_used(player: Player) -> void:
	panel.open(player)


func _on_panel_changed() -> void:
	enabled = panel.user == null
