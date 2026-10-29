class_name PipRow
extends HBoxContainer
## A level as pips on a holo card (an upgrade's MK, a skill's ranks, a weapon part's MK; like the
## pips on the weapons and the helmet): lit up to the level, dark after it, faint beyond the ship's
## reach; a level under way fills its pip from the left.

const LIT := Color(0.3, 0.85, 1.0)
const DARK := Color(0.12, 0.18, 0.22)
## Levels beyond the ship's reach (they come with the next planets).
const OUT_OF_REACH := Color(0.12, 0.18, 0.22, 0.35)

## The size of a pip, in the card's pixels.
@export var pip_size := Vector2(20.0, 14.0)


## Shows `level` of `max_level` (those above `cap` faint). With `progress` (0–1), the level after
## `level` is under way: its pip fills from the left.
func show_level(level: int, max_level: int, cap: int = 99, progress: float = -1.0) -> void:
	while get_child_count() < max_level:
		var pip := ColorRect.new()
		pip.custom_minimum_size = pip_size
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.color = LIT
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_child(fill)
		add_child(pip)
	while get_child_count() > max_level:
		var last: Node = get_child(-1)
		remove_child(last)
		last.queue_free()
	for i: int in max_level:
		var pip := get_child(i) as ColorRect
		pip.color = LIT if i < level else (DARK if i < cap else OUT_OF_REACH)
		var fill := pip.get_node(^"Fill") as ColorRect
		fill.visible = i == level and progress >= 0.0
		fill.size = Vector2(pip_size.x * clampf(progress, 0.0, 1.0), pip_size.y)
