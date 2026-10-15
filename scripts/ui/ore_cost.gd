class_name OreCost
extends HFlowContainer
## A cost in ore on a holo card: per ore type a chip in its color and "cost / in the hold", red
## where the hold is short (an upgrade's next level, a skill's next rank).

const MISSING_COLOR := Color(1.0, 0.4, 0.35)
const ORE_CHIP_SIZE := Vector2(22.0, 22.0)

## The cost shown, and its amount label per ore type.
var _cost: Dictionary[OreType, int] = {}
var _labels: Dictionary[OreType, Label] = {}


## Shows `cost` (empty: nothing) next to what `hold` has of each ore.
func show_cost(cost: Dictionary[OreType, int], hold: Dictionary[OreType, float]) -> void:
	if cost != _cost:
		_cost = cost.duplicate()
		for node: Node in get_children():
			remove_child(node)
			node.queue_free()
		_labels.clear()
		for ore_type: OreType in cost:
			var chip := ColorRect.new()
			chip.color = ore_type.color
			chip.custom_minimum_size = ORE_CHIP_SIZE
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			add_child(chip)
			var amount := Label.new()
			# Numbers only: nothing to translate.
			amount.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			add_child(amount)
			_labels[ore_type] = amount
	for ore_type: OreType in _labels:
		var in_hold: float = hold.get(ore_type, 0.0)
		var stored: int = floori(in_hold)
		var label: Label = _labels[ore_type]
		label.text = "%d / %d" % [cost[ore_type], stored]
		if stored < cost[ore_type]:
			label.add_theme_color_override(&"font_color", MISSING_COLOR)
		else:
			label.remove_theme_color_override(&"font_color")
