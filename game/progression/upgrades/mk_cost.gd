class_name MkCost
extends Resource
## What one MK level from MK2 on costs, the same for every upgrade (see `MkCosts`): a common and a
## mid ore, from MK3 on the signature ore of the planet that brought the level, and from MK4 on bars
## of an alloy (that of the previous planet's signature ore, so it can be refined before the level
## opens). An upgrade scales the amounts by its `Upgrade.cost_scale`. Values TBD (playtest).

## The common ore (`OreType.Band.COMMON`) and its amount.
@export var common: OreType
@export var common_amount: int = 0
## The mid ore (`OreType.Band.MID`) and its amount.
@export var mid: OreType
@export var mid_amount: int = 0
## The signature ore of the planet that brought the level, or null (MK2), and its amount.
@export var signature: OreType
@export var signature_amount: int = 0
## The alloy, or null (up to MK3), and its bars.
@export var alloy: AlloyType
@export var alloy_bars: int = 0


## The cost in units per item, the ore amounts scaled by `scale` and rounded to tens, the bars
## rounded to whole ones (at least one).
func cost(scale: float = 1.0) -> Dictionary[ItemType, int]:
	var result: Dictionary[ItemType, int] = {}
	_add(result, common, common_amount, scale)
	_add(result, mid, mid_amount, scale)
	_add(result, signature, signature_amount, scale)
	if alloy and alloy_bars > 0:
		var bars: ItemType = alloy
		result[bars] = maxi(roundi(alloy_bars * scale), 1)
	return result


static func _add(
	result: Dictionary[ItemType, int], ore_type: OreType, amount: int, scale: float
) -> void:
	var scaled: int = roundi(amount * scale / 10.0) * 10
	if ore_type and scaled > 0:
		result[ore_type] = scaled
