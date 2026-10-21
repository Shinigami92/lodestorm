class_name PlayerHold
extends Resource
## A player's own hold: what they brought back over all runs and haven't spent yet, in units per
## item (ores, later alloys), and which items were ever in it. Each player has their own, in their
## own save (like their `Upgrades`), also when they play on someone else's ship: every run's haul
## goes to every player in the session whole (see `Ship.store_haul`), and each pays for their own
## gear from it. The silos in the cargo bay show it (`OreHold`).

## Emitted when the amount of `item` changes (a haul stored, a cost paid).
signal item_changed(item: ItemType, amount: float)

## Units per item; items it never had are missing.
var items: Dictionary[ItemType, float] = {}
## Items ever in it (the silos show the others as unknown), also once spent.
var found: Dictionary[ItemType, bool] = {}


## Units of `item` in it.
func amount(item: ItemType) -> float:
	return items.get(item, 0.0)


## Whether `item` was ever in it.
func has_found(item: ItemType) -> bool:
	return found.has(item)


## Adds `units` of `item`.
func add(item: ItemType, units: float) -> void:
	_set_amount(item, amount(item) + units)


## Takes `units` of `item` out (at most what it has). Returns what it took.
func take(item: ItemType, units: float) -> float:
	var taken: float = clampf(units, 0.0, amount(item))
	if taken > 0.0:
		_set_amount(item, amount(item) - taken)
	return taken


## Whether it has `cost` (units per ore type).
func can_pay(cost: Dictionary[OreType, int]) -> bool:
	for ore_type: OreType in cost:
		if amount(ore_type) < cost[ore_type]:
			return false
	return true


## Takes `cost` (units per ore type) out if it's there. Returns whether it paid.
func pay(cost: Dictionary[OreType, int]) -> bool:
	if not can_pay(cost):
		return false
	for ore_type: OreType in cost:
		_set_amount(ore_type, amount(ore_type) - cost[ore_type])
	return true


## Marks `item` as found (its silo shows it from then on) without adding any.
func mark_found(item: ItemType) -> void:
	if found.has(item):
		return
	found[item] = true
	item_changed.emit(item, amount(item))
	emit_changed()


## The ores in it, in units per ore type (for the cards, which show ore costs).
func ores() -> Dictionary[OreType, float]:
	var result: Dictionary[OreType, float] = {}
	for item: ItemType in items:
		if item is OreType:
			result[item as OreType] = items[item]
	return result


func _set_amount(item: ItemType, units: float) -> void:
	items[item] = units
	if units > 0.0:
		found[item] = true
	item_changed.emit(item, units)
	emit_changed()
