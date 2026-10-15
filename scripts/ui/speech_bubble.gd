class_name SpeechBubble
extends Control
## A speech bubble's content (in a transparent `WorldPanel` above the one speaking): the line in a
## dark panel with a cyan frame, and a tail below its middle pointing down at the speaker. It keeps
## to the bottom of its screen and takes only the height the line needs, so the tail stays just
## above the speaker's head. The whole line shows at once (no typing out).

## Width of the tail where it meets the panel, in px of the layout (its height is `%Tail`'s).
const TAIL_WIDTH: float = 44.0

@onready var _layout: Control = %Layout
@onready var _panel: PanelContainer = %Panel
@onready var _text: Label = %Text
@onready var _tail: Control = %Tail


func _ready() -> void:
	_tail.draw.connect(_draw_tail)


## Shows `text` (already translated).
func show_line(text: String) -> void:
	_text.text = text


## The line shown (for tests and probes).
func get_line() -> String:
	return _text.text


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
