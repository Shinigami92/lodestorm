@abstract class_name StationCard
extends PanelContainer
## The menu on a `Station`'s holo card: shows the selected part and what can be done with it.

## The station it belongs to (set by the station).
var station: Station

## Shows `part` (null: nothing selected).
@abstract func show_part(part: StationPart) -> void


## Presses the card's main action (`interact` on a gamepad or keyboard). Returns whether it did
## something.
func press_primary() -> bool:
	return false


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	# Texts set from code are translated already.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label
