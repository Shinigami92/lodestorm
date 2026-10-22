class_name ItemCost
extends HFlowContainer
## A cost on a holo card: per ore type (or alloy) its badge with its name and "cost / in the hold",
## red where the hold is short (an upgrade's next level, a skill's next rank, a miner's build).

const MISSING_COLOR := Color(1.0, 0.4, 0.35)

## The cost shown, and its amount label per item.
var _cost: Dictionary[ItemType, int] = {}
var _labels: Dictionary[ItemType, Label] = {}


## Shows `cost` (empty: nothing) next to what `hold` has of each ore.
func show_cost(cost: Dictionary[OreType, int], hold: Dictionary[OreType, float]) -> void:
	var items: Dictionary[ItemType, int] = {}
	for ore_type: OreType in cost:
		items[ore_type] = cost[ore_type]
	var stored: Dictionary[ItemType, float] = {}
	for ore_type: OreType in hold:
		stored[ore_type] = hold[ore_type]
	show_items(items, stored)


## Shows `cost` in units per item (ores and alloys; empty: nothing) next to what `hold` has of each.
func show_items(cost: Dictionary[ItemType, int], hold: Dictionary[ItemType, float]) -> void:
	if cost != _cost:
		_cost = cost.duplicate()
		for node: Node in get_children():
			remove_child(node)
			node.queue_free()
		_labels.clear()
		for item_type: ItemType in cost:
			var item := HBoxContainer.new()
			item.add_theme_constant_override(&"separation", 8)
			item.add_child(ItemBadge.new(item_type))
			var amount := Label.new()
			# Numbers only: nothing to translate.
			amount.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			item.add_child(amount)
			add_child(item)
			_labels[item_type] = amount
	for item_type: ItemType in _labels:
		var in_hold: float = hold.get(item_type, 0.0)
		var stored: int = floori(in_hold)
		var label: Label = _labels[item_type]
		label.text = "%d / %d" % [cost[item_type], stored]
		if stored < cost[item_type]:
			label.add_theme_color_override(&"font_color", MISSING_COLOR)
		else:
			label.remove_theme_color_override(&"font_color")
