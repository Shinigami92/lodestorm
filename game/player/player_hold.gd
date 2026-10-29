class_name PlayerHold
extends Resource
## A player's own hold: what they brought back over all runs and haven't spent yet, in units per
## item (ores, the alloys' bars), and which items were ever in it. Each player has their own, in
## their own save (like their `Upgrades`), also when they play on someone else's ship: every run's
## haul goes to every player in the session whole (see `Ship.store_haul`), and each pays for their
## own gear from it. The silos in the cargo bay show it (`OreHold`).

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


## Whether it has `cost`, in units per item (ores and alloys).
func can_pay(cost: Dictionary[ItemType, int]) -> bool:
	for item: ItemType in cost:
		if amount(item) < cost[item]:
			return false
	return true


## Takes `cost` (units per item) out if it's there. Returns whether it paid.
func pay(cost: Dictionary[ItemType, int]) -> bool:
	if not can_pay(cost):
		return false
	for item: ItemType in cost:
		_set_amount(item, amount(item) - cost[item])
	return true


## Puts `cost` (units per item) back in (a job or a build stopped).
func refund(cost: Dictionary[ItemType, int]) -> void:
	for item: ItemType in cost:
		add(item, cost[item])


## Marks `item` as found (its silo shows it from then on) without adding any.
func mark_found(item: ItemType) -> void:
	if found.has(item):
		return
	found[item] = true
	item_changed.emit(item, amount(item))
	emit_changed()


## What's saved: units per item and the items ever in it (sorted).
func save_data() -> Dictionary:
	var saved_found: Array = SaveData.uids_of(found.keys())
	saved_found.sort()
	return {"items": SaveData.numbers_by_uid(items), "found": saved_found}


## Reads what a save has (`save_data`) into it. Returns whether all of it read.
func load_data(saved: Variant) -> bool:
	if saved == null:
		return true
	var data: Dictionary = saved if saved is Dictionary else {}
	var saved_items: Variant = data.get("items", {})
	var saved_found: Variant = data.get("found", [])
	if not saved is Dictionary or not saved_items is Dictionary or not saved_found is Array:
		return SaveData.skipped("hold", saved)
	var entries: Dictionary = saved_items
	var read: Dictionary = SaveData.load_numbers(entries, ItemType, 0.0, "hold entry")
	for item: ItemType in read:
		var units: float = read[item]
		add(item, units)
	var listed: Array = saved_found
	var known: Array = SaveData.load_uids(listed, ItemType, "found item")
	for item: ItemType in known:
		mark_found(item)
	return read.size() == entries.size() and known.size() == listed.size()


func _set_amount(item: ItemType, units: float) -> void:
	items[item] = units
	if units > 0.0:
		found[item] = true
	item_changed.emit(item, units)
	emit_changed()
