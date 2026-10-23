class_name RampHint
extends Node3D
## A hint above the ramp button (see GAME_DESIGN.md, Death & persistence): health carries over
## between runs, so the first time the local player stands at the button hurt with the ramp up, a
## bubble says where to heal. It shows once per player (`PlayerHints`, saved with the player), as
## long as that player stays there.

## The hint in `PlayerHints`.
const HINT: StringName = &"medical_bay"
## Gap between the button and the bubble's tail, in m.
const GAP: float = 0.25

## The ship whose ramp button it sits on.
var ship: Ship
## The player it shows for right now, or null.
var shown_for: Player

@onready var _bubble: WorldPanel = $Bubble


func _ready() -> void:
	_bubble.visible = false


func _process(_delta: float) -> void:
	if not ship:
		return
	if shown_for:
		if is_instance_valid(shown_for) and _applies_to(shown_for):
			_place()
		else:
			_hide()
		return
	for node: Node in get_tree().get_nodes_in_group(Player.GROUP):
		var player := node as Player
		if player.local and not player.hints.is_seen(HINT) and _applies_to(player):
			_show(player)
			return


## Whether `player` is at the ramp button, hurt, with the ramp up.
func _applies_to(player: Player) -> bool:
	return (
		player.interact_target == ship.ramp_button
		and not player.dead
		and player.health < player.max_health()
		and not ship.ramp_open
	)


func _show(player: Player) -> void:
	shown_for = player
	player.hints.mark_seen(HINT)
	(_bubble.content as SpeechBubble).show_line(
		tr("Not at full health: the medical bay is at the nose.")
	)
	_bubble.visible = true
	_bubble.set_on_top(true)
	_place()


func _hide() -> void:
	shown_for = null
	_bubble.visible = false
	_bubble.set_on_top(false)


## Keeps the bubble above the button, facing the camera.
func _place() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return
	var view: Basis = camera.global_basis.orthonormalized()
	_bubble.global_transform = Transform3D(
		view, global_position + view.y * (_bubble.size.y * 0.5 + GAP)
	)
