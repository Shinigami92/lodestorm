class_name OreCost
extends HFlowContainer
## A cost in ore on a holo card: per ore type its badge with its name and "cost / in the hold",
## red where the hold is short (an upgrade's next level, a skill's next rank).

const MISSING_COLOR := Color(1.0, 0.4, 0.35)

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
			var item := HBoxContainer.new()
			item.add_theme_constant_override(&"separation", 8)
			item.add_child(OreBadge.new(ore_type))
			var amount := Label.new()
			# Numbers only: nothing to translate.
			amount.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			item.add_child(amount)
			add_child(item)
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
