class_name ExchangeCard
extends StationCard
## The holo card of the ore exchange (`ExchangeStation`): a row per hopper, what goes in and what
## comes out (arrows either side picking the ore, its badge and name, the amount, and how much the
## hold has; the selected hopper's heading in amber), the amount coming out (buttons taking off or
## adding 10, 5 and 1 either side of the number), the rate, "Exchange" and "Close". Without an ore
## to put in or one to get out, a line says why.

## The amount buttons, by what they add.
var _count_buttons: Dictionary[int, Button] = {}

@onready var _in_heading: Label = %InHeading
@onready var _in_prev: Button = %InPrev
@onready var _in_badge: CenterContainer = %InBadge
@onready var _in_amount: Label = %InAmount
@onready var _in_next: Button = %InNext
@onready var _in_have: Label = %InHave
@onready var _out_heading: Label = %OutHeading
@onready var _out_prev: Button = %OutPrev
@onready var _out_badge: CenterContainer = %OutBadge
@onready var _out_amount: Label = %OutAmount
@onready var _out_next: Button = %OutNext
@onready var _out_have: Label = %OutHave
@onready var _count_row: HBoxContainer = %CountRow
@onready var _count: Label = %Count
@onready var _rate: Label = %Rate
@onready var _status: Label = %Status
@onready var _action: Button = %Action
@onready var _close: Button = %Close


func _ready() -> void:
	_in_prev.pressed.connect(_on_ore_pressed.bind(true, -1))
	_in_next.pressed.connect(_on_ore_pressed.bind(true, 1))
	_out_prev.pressed.connect(_on_ore_pressed.bind(false, -1))
	_out_next.pressed.connect(_on_ore_pressed.bind(false, 1))
	for amount: int in ExchangeStation.COUNT_BUTTONS:
		var button := Button.new()
		button.name = "Count%s%d" % ["Plus" if amount > 0 else "Minus", absi(amount)]
		# Numbers only: nothing to translate.
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.focus_mode = Control.FOCUS_NONE
		# The body text's size: six of them share a row with the number.
		button.add_theme_font_size_override(&"font_size", 26)
		button.text = "%+d" % amount
		button.pressed.connect(_on_count_pressed.bind(amount))
		_count_row.add_child(button)
		# The minus buttons go before the number, the plus ones after it.
		if amount < 0:
			_count_row.move_child(button, _count.get_index())
		_count_buttons[amount] = button
	_action.pressed.connect(press_primary)
	_close.pressed.connect(_on_close_pressed)


func show_part(part: StationPart) -> void:
	var exchange := station as ExchangeStation
	visible = part != null and exchange != null
	if not visible:
		return
	var hold: PlayerHold = exchange.get_hold()
	var count: int = exchange.get_count()
	var ore_in: OreType = exchange.ore_in
	var ore_out: OreType = exchange.ore_out
	_show_row(
		ore_in,
		count * OreExchange.RATE,
		hold,
		[_in_heading, _in_amount, _in_have],
		_in_badge,
		part == exchange.get_in_hopper()
	)
	_show_row(
		ore_out,
		count,
		hold,
		[_out_heading, _out_amount, _out_have],
		_out_badge,
		part == exchange.get_out_hopper()
	)
	# A number only: "Amount" stands above the row.
	_count.text = str(count)
	for amount: int in _count_buttons:
		_count_buttons[amount].disabled = (
			count <= 1 if amount < 0 else count >= exchange.get_max_count()
		)
	_rate.text = tr("Rate: %d in, 1 out.") % OreExchange.RATE
	_status.visible = not ore_in or not ore_out
	if not ore_in:
		_status.text = (
			tr("Your hold has no ore to trade: at least %d of one kind go in.") % OreExchange.RATE
		)
	elif not ore_out:
		_status.text = tr("There's no other ore you could get yet.")
	_action.disabled = not exchange.can_trade()


func press_primary() -> bool:
	var exchange := station as ExchangeStation
	return exchange != null and exchange.trade()


## The button that trades (for tests and probes).
func get_action_button() -> Button:
	return _action


## The button adding `amount` (for tests and probes), or null.
func get_count_button(amount: int) -> Button:
	return _count_buttons.get(amount)


## The line saying what's in the way (for tests).
func get_status() -> Label:
	return _status


## One hopper's row: `ore` (none: a dash) and `amount` of it, what `hold` has of it, its heading
## (`labels`: heading, amount, hold) in amber when `selected`.
func _show_row(
	ore: OreType,
	amount: int,
	hold: PlayerHold,
	labels: Array[Label],
	badge: CenterContainer,
	selected: bool
) -> void:
	labels[0].modulate = CardPalette.STATUS if selected else CardPalette.NOTE
	_set_badge(badge, ore)
	labels[1].text = "× %d" % amount if ore else "–"
	labels[2].visible = ore != null
	if ore:
		labels[2].text = tr("In the hold: %d") % floori(hold.amount(ore))


func _set_badge(badge: CenterContainer, item: ItemType) -> void:
	var shown := badge.get_child(0) as ItemBadge if badge.get_child_count() > 0 else null
	if not shown:
		shown = ItemBadge.new(null)
		badge.add_child(shown)
	shown.item = item
	shown.visible = item != null


func _on_ore_pressed(going_in: bool, step_by: int) -> void:
	var exchange := station as ExchangeStation
	if exchange:
		exchange.step_ore(
			step_by, exchange.get_in_hopper() if going_in else exchange.get_out_hopper()
		)


func _on_count_pressed(step_by: int) -> void:
	var exchange := station as ExchangeStation
	if exchange:
		exchange.step_count(step_by)


func _on_close_pressed() -> void:
	if station:
		station.close()
