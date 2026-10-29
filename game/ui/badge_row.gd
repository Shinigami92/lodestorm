class_name BadgeRow
extends HFlowContainer
## A row of item badges with their names on a holo card (a destination's ores, the ores a heat
## shield plate needs, a recipe), wrapping when they don't fit. A null item shows as "?" (one not
## known yet). The badges are made again only when what's shown changes.

## The items shown (null: "?") and the amounts after them.
var _shown: Array = []
var _amounts: Dictionary = {}


## Shows `items` in their order (null: "?"); `amounts`: per item a number after its badge (a
## recipe's units per bar).
func show_items(items: Array, amounts: Dictionary = {}) -> void:
	if items == _shown and amounts == _amounts and get_child_count() == items.size():
		return
	_shown = items.duplicate()
	_amounts = amounts.duplicate()
	for node: Node in get_children():
		node.free()
	for item: ItemType in items:
		if not item:
			var unknown := Label.new()
			unknown.text = "?"
			unknown.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			unknown.modulate = CardPalette.NOTE
			add_child(unknown)
		elif amounts.has(item):
			var entry := HBoxContainer.new()
			entry.add_theme_constant_override(&"separation", 8)
			entry.add_child(ItemBadge.new(item))
			var amount := Label.new()
			# A number only: nothing to translate.
			amount.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			amount.text = str(amounts[item])
			entry.add_child(amount)
			add_child(entry)
		else:
			add_child(ItemBadge.new(item))


## The items shown, in their order (null: "?").
func get_items() -> Array:
	return _shown.duplicate()
