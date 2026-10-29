@abstract class_name StationCard
extends PanelContainer
## The menu on a `Station`'s holo card: shows the selected part and what can be done with it. A
## `%Close` button in its scene closes the station.

## The station it belongs to (set by the station).
var station: Station

## Shows `part` (null: nothing selected).
@abstract func show_part(part: StationPart) -> void


## Presses the card's main action (`interact` on a gamepad or keyboard). Returns whether it did
## something.
func press_primary() -> bool:
	return false


## Dims `items` (a row of the card) for what can't be had yet, or shows them normally.
static func dim(items: Array, dimmed: bool) -> void:
	for item: CanvasItem in items:
		item.modulate = CardPalette.DIMMED if dimmed else Color.WHITE


# Called at every level of the script (unlike `_ready`), so cards keep their own `_ready`.
func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		var close := get_node_or_null(^"%Close") as Button
		if close:
			close.pressed.connect(_on_close_pressed)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	# Texts set from code are translated already.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label


## Why nothing can be done while a mission is underway.
func _locked_text() -> String:
	return tr("Locked until everyone is back aboard.")


func _on_close_pressed() -> void:
	if station:
		station.close()
