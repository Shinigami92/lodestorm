class_name RadioBubble
extends Control
## A radio call's content (in a transparent `WorldPanel` beside the player, see `PlayerRadio`): a
## speech bubble's dark panel without a tail, its top row an antenna and who calls ("Tamsin ·
## Radio") in their color, the line below. It keeps to the bottom right of its screen and takes
## only the size the line needs (a short call stays narrow, close to the player), wrapping a long
## one at the screen's width.

@onready var _layout: Control = %Layout
@onready var _panel: PanelContainer = %Panel
@onready var _caller: Label = %Caller
@onready var _text: Label = %Text
@onready var _antenna: Control = %Antenna


func _ready() -> void:
	_antenna.draw.connect(_draw_antenna)


## Shows `text` (already translated) as a call from `caller_name` in `color`.
func show_call(caller_name: String, color: Color, text: String) -> void:
	_caller.text = "%s · %s" % [caller_name, tr("Radio")]
	_caller.add_theme_color_override(&"font_color", color)
	_antenna.modulate = color
	_antenna.queue_redraw()
	_text.text = text
	# Autowrap gives a label no width of its own: as wide as the line, at most the screen's.
	var style: StyleBox = _panel.get_theme_stylebox(&"panel")
	var widest: float = size.x - style.get_margin(SIDE_LEFT) - style.get_margin(SIDE_RIGHT)
	var font: Font = _text.get_theme_font(&"font")
	var font_size: int = _text.get_theme_font_size(&"font_size")
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text.custom_minimum_size.x = minf(ceilf(width) + 2.0, widest)


## The line shown (for tests and probes).
func get_line() -> String:
	return _text.text


## Who calls, as the top row shows it.
func get_caller() -> String:
	return _caller.text


## The size its content needs (for the fit test).
func get_needed_size() -> Vector2:
	return _layout.get_combined_minimum_size()


## The antenna: a mast with a dot on top and two waves on each side, in white (tinted by its
## `modulate`).
func _draw_antenna() -> void:
	var size_now: Vector2 = _antenna.size
	var top := Vector2(size_now.x * 0.5, size_now.y * 0.4)
	var width: float = 3.0
	_antenna.draw_line(top, Vector2(top.x, size_now.y), Color.WHITE, width, true)
	_antenna.draw_circle(top, 4.0, Color.WHITE, true, -1.0, true)
	for ring: int in 2:
		var radius: float = 9.0 + ring * 7.0
		_antenna.draw_arc(top, radius, PI * 0.75, PI * 1.25, 8, Color.WHITE, width, true)
		_antenna.draw_arc(top, radius, -PI * 0.25, PI * 0.25, 8, Color.WHITE, width, true)
