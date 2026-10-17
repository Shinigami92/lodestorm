class_name MkCost
extends Resource
## What one MK level from MK2 on costs, the same for every upgrade (see `MkCosts`): a common and a
## mid ore, and from MK3 on the signature ore of the planet that brought the level. An upgrade
## scales the amounts by its `Upgrade.cost_scale`. Values TBD (playtest).

## The common ore (`OreType.Band.COMMON`) and its amount.
@export var common: OreType
@export var common_amount: int = 0
## The mid ore (`OreType.Band.MID`) and its amount.
@export var mid: OreType
@export var mid_amount: int = 0
## The signature ore of the planet that brought the level, or null (MK2), and its amount.
@export var signature: OreType
@export var signature_amount: int = 0


## The cost in units per ore type, the amounts scaled by `scale` and rounded to tens.
func cost(scale: float = 1.0) -> Dictionary[OreType, int]:
	var result: Dictionary[OreType, int] = {}
	_add(result, common, common_amount, scale)
	_add(result, mid, mid_amount, scale)
	_add(result, signature, signature_amount, scale)
	return result


static func _add(
	result: Dictionary[OreType, int], ore_type: OreType, amount: int, scale: float
) -> void:
	var scaled: int = roundi(amount * scale / 10.0) * 10
	if ore_type and scaled > 0:
		result[ore_type] = scaled
