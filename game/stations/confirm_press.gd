class_name ConfirmPress
extends RefCounted
## A button that acts only on its second press for the same thing within `WINDOW` (e.g. a card's
## "Stop"): the first press arms it, and the card asks "for sure".

## Seconds the first press waits for the second.
const WINDOW: float = 4.0

var _item: Object
var _until: float = -INF


## Whether the first press for `item` waits for the second.
func is_armed(item: Object) -> bool:
	return item != null and item == _item and _seconds() < _until


## Presses for `item`. Returns whether it was the second press (act now); the first only arms it.
func press(item: Object) -> bool:
	if is_armed(item):
		reset()
		return true
	_item = item
	_until = _seconds() + WINDOW
	return false


## Forgets a first press.
func reset() -> void:
	_item = null
	_until = -INF


static func _seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
