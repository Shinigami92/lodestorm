class_name BoardMarker
extends Control
## The sign at the start of a quest board line (see `BoardScreen`): a diamond for a quest (filled
## for the tracked one, like its markers in the world), an arrow for the done quests' group (down
## while it's open), a dot for a message (filled while it's unheard, like the round marker of
## something new in the world).

enum Shape { NONE, ACTIVE, TRACKED, CLOSED, OPEN, UNHEARD, HEARD }

## Its size, in px.
const SIZE: float = 24.0

var shape: Shape = Shape.NONE


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var middle: Vector2 = size * 0.5
	var half: float = SIZE * 0.4
	var color: Color = CardPalette.STATUS
	match shape:
		Shape.ACTIVE, Shape.TRACKED:
			var diamond := PackedVector2Array(
				[
					middle + Vector2(0.0, -half),
					middle + Vector2(half, 0.0),
					middle + Vector2(0.0, half),
					middle + Vector2(-half, 0.0),
				]
			)
			if shape == Shape.TRACKED:
				draw_colored_polygon(diamond, color)
			else:
				diamond.append(diamond[0])
				draw_polyline(diamond, color, 2.0, true)
		Shape.UNHEARD:
			draw_circle(middle, half * 0.7, color, true, -1.0, true)
		Shape.HEARD:
			draw_circle(middle, half * 0.7, Color(color, 0.6), false, 2.0, true)
		Shape.CLOSED:
			draw_colored_polygon(
				PackedVector2Array(
					[
						middle + Vector2(-half * 0.6, -half),
						middle + Vector2(half * 0.8, 0.0),
						middle + Vector2(-half * 0.6, half),
					]
				),
				color
			)
		Shape.OPEN:
			draw_colored_polygon(
				PackedVector2Array(
					[
						middle + Vector2(-half, -half * 0.6),
						middle + Vector2(half, -half * 0.6),
						middle + Vector2(0.0, half * 0.8),
					]
				),
				color
			)
