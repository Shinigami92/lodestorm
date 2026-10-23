class_name BedCard
extends StationCard
## The holo card of a bed (`BedStation`): "Sleep" quits the game; it says whether the progress is
## saved or the run underway is lost.

@onready var _note: Label = %Note
@onready var _sleep: Button = %Sleep
@onready var _close: Button = %Close


func _ready() -> void:
	_sleep.pressed.connect(press_primary)
	_close.pressed.connect(_on_close_pressed)


func show_part(part: StationPart) -> void:
	var bed := station as BedStation
	visible = part != null and bed != null
	if not visible:
		return
	show_state(bed.loses_run())


## Shows what sleeping does now: lose the run underway, or save and quit.
func show_state(loses_run: bool) -> void:
	if loses_run:
		_note.text = tr("A run is underway: sleeping now loses it.")
		_note.add_theme_color_override(&"font_color", CardPalette.WARNING)
	else:
		_note.text = tr("Ends the game here. Your progress is saved.")
		_note.add_theme_color_override(&"font_color", CardPalette.NOTE)


func press_primary() -> bool:
	var bed := station as BedStation
	return bed != null and bed.sleep()


func _on_close_pressed() -> void:
	if station:
		station.close()
