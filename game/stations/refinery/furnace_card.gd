class_name FurnaceCard
extends StationCard
## The holo card of a furnace (`FurnaceStation`). A locked furnace's says only that it's cold. A
## free one's picks the recipe (its alloy's badge and name and tier; an unknown one as "?" with the
## ores of it found so far) and the number of bars (buttons taking off or adding 10, 5 and 1 either
## side of the number), shows what they cost next to what the hold has (red where it's short) and
## how long they take, and "Start". A running one's shows its alloy, the bars done, how far the bar
## in the furnace is, the time left, and "Stop" (pressed twice).

const NOTE_COLOR := Color(1.0, 1.0, 1.0, 0.75)

## What `_found` shows, so it's only rebuilt when it changes.
var _found_shown: Array[OreType] = []
## The bar buttons, by what they add.
var _bar_buttons: Dictionary[int, Button] = {}

@onready var _badge: CenterContainer = %Badge
@onready var _title: Label = %Title
@onready var _info: Label = %Info
@onready var _picker: VBoxContainer = %Picker
@onready var _recipe_prev: Button = %RecipePrev
@onready var _recipe_name: Label = %RecipeName
@onready var _recipe_next: Button = %RecipeNext
@onready var _found: HFlowContainer = %Found
@onready var _bar_count: HBoxContainer = %BarCount
@onready var _bars: Label = %Bars
@onready var _cost_row: HFlowContainer = %CostRow
@onready var _cost: ItemCost = %Cost
@onready var _time: Label = %Time
@onready var _status: Label = %Status
@onready var _action: Button = %Action
@onready var _close: Button = %Close


func _ready() -> void:
	_recipe_prev.pressed.connect(_on_recipe_pressed.bind(-1))
	_recipe_next.pressed.connect(_on_recipe_pressed.bind(1))
	for amount: int in FurnaceStation.BAR_BUTTONS:
		var button := Button.new()
		button.name = "Bars%s%d" % ["Plus" if amount > 0 else "Minus", absi(amount)]
		# Numbers only: nothing to translate.
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.focus_mode = Control.FOCUS_NONE
		# The body text's size: six of them share a row with the number.
		button.add_theme_font_size_override(&"font_size", 26)
		button.text = "%+d" % amount
		button.pressed.connect(_on_bars_pressed.bind(amount))
		_bar_count.add_child(button)
		# The minus buttons go before the number, the plus ones after it.
		if amount < 0:
			_bar_count.move_child(button, _bars.get_index())
		_bar_buttons[amount] = button
	_action.pressed.connect(press_primary)
	_close.pressed.connect(_on_close_pressed)


func show_part(part: StationPart) -> void:
	var furnace := station as FurnaceStation
	visible = part != null and furnace != null
	if not visible:
		return
	if not furnace.is_unlocked():
		_show_cold()
		return
	var batch: AlloyBatch = furnace.get_batch()
	if batch:
		_show_running(furnace, batch)
	else:
		_show_free(furnace)


func press_primary() -> bool:
	var furnace := station as FurnaceStation
	if not furnace or not furnace.is_unlocked():
		return false
	if furnace.get_batch():
		return furnace.stop()
	return furnace.start()


## The button that starts or stops (for tests and probes).
func get_action_button() -> Button:
	return _action


## The button adding `amount` bars (for tests and probes), or null.
func get_bar_button(amount: int) -> Button:
	return _bar_buttons.get(amount)


## The line saying what's in the way (for tests).
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


func _show_cold() -> void:
	_set_badge(null)
	_title.text = tr("Furnace")
	_info.visible = false
	_picker.visible = false
	_time.visible = false
	_status.visible = true
	_status.text = tr("This furnace is cold.")
	_action.visible = false


func _show_running(furnace: FurnaceStation, batch: AlloyBatch) -> void:
	var now: float = Time.get_unix_time_from_system()
	_set_badge(batch.alloy)
	_title.text = batch.alloy.get_display_name()
	_info.visible = true
	_info.text = (
		tr("Bars done: %d / %d") % [batch.done, batch.bars]
		+ "\n"
		+ tr("Bar in the furnace: %d %%") % floori(batch.bar_progress(now) * 100.0)
	)
	_picker.visible = false
	_time.visible = true
	_time.text = tr("Time left: %s") % duration_text(batch.time_left(now))
	_status.visible = furnace.is_locked() or furnace.is_stop_armed()
	if furnace.is_locked():
		_status.text = tr("Locked until everyone is back aboard.")
	elif furnace.is_stop_armed():
		_status.text = tr("Stop? The bars done stay, the ore of the others goes back to the hold.")
	_action.visible = true
	_action.text = tr("Stop for sure") if furnace.is_stop_armed() else tr("Stop")
	_action.disabled = not furnace.can_stop()


func _show_free(furnace: FurnaceStation) -> void:
	var alloy: AlloyType = furnace.recipe
	var hold: PlayerHold = furnace.user.hold if furnace.user else PlayerHold.new()
	var known: bool = alloy.is_known(hold)
	_set_badge(alloy if known else null)
	_title.text = tr("Furnace")
	_info.visible = false
	_picker.visible = true
	_recipe_name.text = (
		(tr("%s (tier %d)") % [alloy.get_display_name(), alloy.tier])
		if known
		else tr("Unknown alloy (tier %d)") % alloy.tier
	)
	var found: Array[OreType] = []
	if not known:
		found = alloy.found_ores(hold)
	_show_found(found, not known)
	var bars: int = furnace.get_bars()
	# A number only: "Bars" stands above the row.
	_bars.text = str(bars)
	for amount: int in _bar_buttons:
		_bar_buttons[amount].disabled = bars <= 1 if amount < 0 else bars >= furnace.get_max_bars()
	_cost_row.visible = known
	if known:
		_cost.show_cost(alloy.cost(bars), hold.ores())
	_time.visible = known
	_time.text = tr("Takes %s") % duration_text(bars * alloy.seconds_per_bar)
	_status.visible = furnace.is_locked() or not known
	if furnace.is_locked():
		_status.text = tr("Locked until everyone is back aboard.")
	elif not known:
		_status.text = tr("Its recipe shows once all its ores were in the hold.")
	_action.visible = true
	_action.text = tr("Start")
	_action.disabled = not furnace.can_start()


## Shows `ores` (the ores of an unknown recipe found so far) and a "?" after them; `shown`: the row
## shows at all.
func _show_found(ores: Array[OreType], shown: bool) -> void:
	_found.visible = shown
	if ores == _found_shown and _found.get_child_count() > 0:
		return
	_found_shown = ores.duplicate()
	for node: Node in _found.get_children():
		_found.remove_child(node)
		node.queue_free()
	for ore_type: OreType in ores:
		_found.add_child(ItemBadge.new(ore_type))
	var unknown := _label("?")
	unknown.modulate = NOTE_COLOR
	_found.add_child(unknown)


func _set_badge(item: ItemType) -> void:
	var shown := _badge.get_child(0) as ItemBadge if _badge.get_child_count() > 0 else null
	if not shown:
		shown = ItemBadge.new(null, false)
		_badge.add_child(shown)
	shown.item = item
	_badge.visible = item != null


func _on_recipe_pressed(step_by: int) -> void:
	var furnace := station as FurnaceStation
	if furnace:
		furnace.step_recipe(step_by)


func _on_bars_pressed(step_by: int) -> void:
	var furnace := station as FurnaceStation
	if furnace:
		furnace.step_bars(step_by)


func _on_close_pressed() -> void:
	if station:
		station.close()
