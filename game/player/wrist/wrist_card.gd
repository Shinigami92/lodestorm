class_name WristCard
extends Control
## The wrist display's card (in a transparent `WorldPanel` beside the player, see `WristDisplay`).
## Its first tab is the cargo: per ore type carried its badge, name and units (commonest first),
## and the total. More tabs follow (the quest log). It keeps to the bottom of its screen and takes
## only the height its content needs.

const FONT_SIZE: int = 26

## The cargo shown, per ore type.
var _shown: Dictionary[OreType, float] = {}

@onready var _panel: Control = %Panel
@onready var _rows: GridContainer = %Rows
@onready var _empty: Label = %Empty
@onready var _total: Label = %Total


func _ready() -> void:
	show_cargo({})


## Shows `cargo` (units per ore type).
func show_cargo(cargo: Dictionary[OreType, float]) -> void:
	if cargo == _shown and is_node_ready() and _rows.get_child_count() > 0:
		return
	_shown = cargo.duplicate()
	for node: Node in _rows.get_children():
		_rows.remove_child(node)
		node.queue_free()
	var sum: float = 0.0
	for ore_type: OreType in OreCatalog.sorted(cargo.keys()):
		var amount: float = cargo[ore_type]
		if amount <= 0.0:
			continue
		sum += amount
		_rows.add_child(_badge(ore_type))
		var name_label := Label.new()
		name_label.text = ore_type.get_display_name()
		name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
		_rows.add_child(name_label)
		var amount_label := Label.new()
		# Numbers only: nothing to translate.
		amount_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		amount_label.text = "%d" % floori(amount)
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
		_rows.add_child(amount_label)
	_rows.visible = sum > 0.0
	_empty.visible = sum <= 0.0
	_total.visible = sum > 0.0
	_total.text = tr("Total: %d") % floori(sum)


## Ore types shown, commonest first (for tests and probes).
func get_shown_ores() -> Array[OreType]:
	var result: Array[OreType] = []
	for ore_type: OreType in OreCatalog.sorted(_shown.keys()):
		if _shown[ore_type] > 0.0:
			result.append(ore_type)
	return result


## The size its content needs (for the fit test).
func get_needed_size() -> Vector2:
	return _panel.get_combined_minimum_size()


func _badge(ore_type: OreType) -> Control:
	var badge := OreBadge.new(ore_type, false)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return badge
