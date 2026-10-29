@abstract class_name OfferCard
extends StationCard
## A holo card offering something that costs ore and takes time (an upgrade level, a skill rank, a
## miner, a furnace's bars): what it costs next to what the hold has (red where it's short), how
## long it takes, why it can't be had, and its button (`interact` presses it); once under way, the
## time left and "Stop" (pressed twice: "Stop for sure", the cost back). Its scene has `%CostRow`
## (with an `ItemCost` `%Cost`), `%Time`, `%Status` and `%Action`.

@onready var _cost_row: Control = %CostRow
@onready var _cost: ItemCost = %Cost
@onready var _time: Label = %Time
@onready var _status: Label = %Status
@onready var _action: Button = %Action


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		(get_node(^"%Action") as Button).pressed.connect(press_primary)


## Shows the offer: `cost` next to what `hold` has (empty: no cost row), how long it takes
## (`seconds`; negative: not shown), `action` on the button (enabled when `can_start`), and below
## why it can't be had: a mission underway (`locked`), else `note` (empty: nothing). Only what can
## be started says how long it takes (the card keeps its height).
func show_offer(
	cost: Dictionary[ItemType, int],
	hold: Dictionary[ItemType, float],
	seconds: float,
	action: String,
	can_start: bool,
	locked: bool = false,
	note: String = ""
) -> void:
	_cost_row.visible = not cost.is_empty()
	_cost.show_cost(cost, hold)
	show_status(locked, note)
	_time.visible = seconds >= 0.0 and not _status.visible
	_time.text = tr("Takes %s") % duration_text(maxf(seconds, 0.0))
	_action.text = action
	_action.disabled = not can_start


## Shows what's under way: `time_left` (seconds) and "Stop" (enabled when `can_stop`), once
## `armed` "Stop for sure" with `armed_note` below (empty: the whole cost goes back); `locked`: a
## mission is underway.
func show_running(
	time_left: float,
	can_stop: bool,
	armed: bool = false,
	locked: bool = false,
	armed_note: String = ""
) -> void:
	_cost_row.visible = false
	_time.visible = true
	_time.text = tr("Time left: %s") % duration_text(time_left)
	if armed and not armed_note:
		armed_note = tr("Stop? The whole cost goes back to the hold.")
	show_status(locked, armed_note if armed else "")
	_action.text = tr("Stop for sure") if armed else tr("Stop")
	_action.disabled = not can_stop


## Shows why nothing can be done: a mission underway (`locked`), else `note` (empty: the line
## hides).
func show_status(locked: bool, note: String = "") -> void:
	_status.text = _locked_text() if locked else note
	_status.visible = _status.text != ""


## The card's button (for tests and probes).
func get_action_button() -> Button:
	return _action


## The line saying how long it takes, or the time left of what's under way (for tests).
func get_time() -> Label:
	return _time


## The line saying why nothing can be done (for tests).
func get_status() -> Label:
	return _status


## Formats `seconds` as hours, minutes and seconds ("1:05:09", "4:30").
static func duration_text(seconds: float) -> String:
	var total: int = ceili(seconds)
	@warning_ignore("integer_division")
	var hours: int = total / 3600
	@warning_ignore("integer_division")
	var minutes: int = (total % 3600) / 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, total % 60]
	return "%d:%02d" % [minutes, total % 60]
