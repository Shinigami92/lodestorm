class_name SpeechBubble
extends Control
## A speech bubble's content (in a transparent `WorldPanel` above the one speaking): the line in a
## dark panel with a cyan frame, and a tail below its middle pointing down at the speaker. It keeps
## to the bottom of its screen and takes only the height the line needs, so the tail stays just
## above the speaker's head. The whole line shows at once (no typing out), names highlighted (see
## `Keywords`).

## Gap between the head and the tail, in m.
const HEAD_GAP: float = 0.05
## Width of the tail where it meets the panel, in px of the layout (its height is `%Tail`'s).
const TAIL_WIDTH: float = 44.0
## The camera's visible height (in m) bubbles outside a talk are sized for: the view while talking
## to the crew (`Npc`'s `view_height`). Wider views scale them up (`view_scale`).
const VIEW_HEIGHT: float = 3.2

var _line: String = ""

@onready var _layout: Control = %Layout
@onready var _panel: PanelContainer = %Panel
@onready var _text: RichTextLabel = %Text
@onready var _tail: Control = %Tail


func _ready() -> void:
	_tail.draw.connect(_draw_tail)


## Keeps `panel` (a bubble's) above `head` (the top of the speaker's head), facing the camera,
## `factor` times its size; unchanged without a camera.
static func place(panel: WorldPanel, head: Vector3, factor: float = 1.0) -> void:
	var camera: Camera3D = panel.get_viewport().get_camera_3d()
	if not camera:
		return
	var view: Basis = camera.global_basis.orthonormalized()
	var lift: float = panel.size.y * 0.5 * factor + HEAD_GAP
	panel.global_transform = Transform3D(
		view.scaled_local(Vector3.ONE * factor), head + view.y * lift
	)


## How much bigger a bubble outside a talk (a remark, a reaction, a radio call) shows than its
## size: the camera's visible height now over `VIEW_HEIGHT` (1 without a camera rig).
static func view_scale(tree: SceneTree) -> float:
	var rig := tree.get_first_node_in_group(IsoCameraRig.GROUP) as IsoCameraRig
	return rig.view_height() * rig.zoom / VIEW_HEIGHT if rig else 1.0


## Shows `text` (already translated).
func show_line(text: String) -> void:
	_line = text
	_text.text = Keywords.highlight(text)


## The line shown, without its highlights (for tests and probes).
func get_line() -> String:
	return _line


## The size its content needs (for the fit test).
func get_needed_size() -> Vector2:
	return _layout.get_combined_minimum_size()


## The tail: the panel's frame color with its fill inside, drawn over the panel's bottom border so
## the two join.
func _draw_tail() -> void:
	var style := _panel.get_theme_stylebox(&"panel") as StyleBoxFlat
	if not style:
		return
	var border: float = style.border_width_bottom
	var middle: float = _tail.size.x * 0.5
	var half: float = TAIL_WIDTH * 0.5
	var tip: float = _tail.size.y
	var frame := PackedVector2Array(
		[Vector2(middle - half, -border), Vector2(middle, tip), Vector2(middle + half, -border)]
	)
	_tail.draw_colored_polygon(frame, style.border_color)
	# The fill keeps a border's width inside the frame on the slanted sides.
	var inner: float = border * 2.2
	var fill := PackedVector2Array(
		[
			Vector2(middle - half + inner, -border),
			Vector2(middle, tip - inner * 2.0),
			Vector2(middle + half - inner, -border),
		]
	)
	_tail.draw_colored_polygon(fill, style.bg_color)
