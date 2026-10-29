class_name FurnaceCard
extends OfferCard
## The holo card of a furnace (`FurnaceStation`). A locked furnace's says only that it's cold. A
## free one's picks the recipe (its alloy's badge and name and tier; an unknown one as "?" with the
## ores of it found so far) and the number of bars (buttons taking off or adding 10, 5 and 1 either
## side of the number), shows what they cost next to what the hold has (red where it's short) and
## how long they take, and "Start". A running one's shows its alloy, the bars done, how far the bar
## in the furnace is, the time left, and "Stop" (pressed twice).

## The bar buttons, by what they add.
var _bar_buttons: Dictionary[int, Button] = {}

@onready var _badge: CenterContainer = %Badge
@onready var _title: Label = %Title
@onready var _info: Label = %Info
@onready var _picker: VBoxContainer = %Picker
@onready var _recipe_prev: Button = %RecipePrev
@onready var _recipe_name: Label = %RecipeName
@onready var _recipe_next: Button = %RecipeNext
@onready var _found: BadgeRow = %Found
@onready var _bar_count: HBoxContainer = %BarCount
@onready var _bars: Label = %Bars


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


## The button adding `amount` bars (for tests and probes), or null.
func get_bar_button(amount: int) -> Button:
	return _bar_buttons.get(amount)


func _show_cold() -> void:
	ItemBadge.show_in(_badge, null, false)
	_title.text = tr("Furnace")
	_info.visible = false
	_picker.visible = false
	_time.visible = false
	show_status(
		false,
		tr("This furnace is cold. Its burner was taken out and sold before the ship was bought.")
	)
	_action.visible = false


func _show_running(furnace: FurnaceStation, batch: AlloyBatch) -> void:
	var now: float = Time.get_unix_time_from_system()
	ItemBadge.show_in(_badge, batch.alloy, false)
	_title.text = batch.alloy.get_display_name()
	_info.visible = true
	_info.text = (
		tr("Bars done: %d / %d") % [batch.done, batch.bars]
		+ "\n"
		+ tr("Bar in the furnace: %d %%") % floori(batch.bar_progress(now) * 100.0)
	)
	_picker.visible = false
	_action.visible = true
	show_running(
		batch.time_left(now),
		furnace.can_stop(),
		furnace.is_stop_armed(),
		furnace.is_locked(),
		tr("Stop? The bars done stay, the ore of the others goes back to the hold.")
	)


func _show_free(furnace: FurnaceStation) -> void:
	var alloy: AlloyType = furnace.recipe
	var hold: PlayerHold = furnace.user.hold if furnace.user else PlayerHold.new()
	var known: bool = alloy.is_known(hold)
	ItemBadge.show_in(_badge, alloy if known else null, false)
	_title.text = tr("Furnace")
	_info.visible = false
	_picker.visible = true
	_recipe_name.text = (
		(tr("%s (tier %d)") % [alloy.get_display_name(), alloy.tier])
		if known
		else tr("Unknown alloy (tier %d)") % alloy.tier
	)
	_found.visible = not known
	if not known:
		var found: Array = alloy.found_ores(hold)
		found.append(null)
		_found.show_items(found)
	var bars: int = furnace.get_bars()
	# A number only: "Bars" stands above the row.
	_bars.text = str(bars)
	for amount: int in _bar_buttons:
		_bar_buttons[amount].disabled = bars <= 1 if amount < 0 else bars >= furnace.get_max_bars()
	var cost: Dictionary[ItemType, int] = {}
	if known:
		cost = alloy.cost(bars)
	_action.visible = true
	show_offer(
		cost,
		hold.items,
		bars * alloy.seconds_per_bar if known else -1.0,
		tr("Start"),
		furnace.can_start(),
		furnace.is_locked(),
		"" if known else tr("Its recipe shows once all its ores were in the hold.")
	)


func _on_recipe_pressed(step_by: int) -> void:
	var furnace := station as FurnaceStation
	if furnace:
		furnace.step_recipe(step_by)


func _on_bars_pressed(step_by: int) -> void:
	var furnace := station as FurnaceStation
	if furnace:
		furnace.step_bars(step_by)
