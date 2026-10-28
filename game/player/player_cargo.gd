class_name PlayerCargo
extends Resource
## The ore a player carries during a run, in units per ore type; no carry limit. Miners' hoses
## fill it (`add`), reloads pay from it and the cargo hatch empties it (`take`), and it's banked
## when the run ends or dropped when the player dies (`take_all`). The canisters on the back show
## it (`CargoRack`), the badge above the player what arrives (`OreArrival`).

## Emitted when the carried amount of `ore_type` changes.
signal ore_changed(ore_type: OreType, amount: float)
## Emitted when ore arrives (`amount` more units of `ore_type`, e.g. from a hose).
signal ore_added(ore_type: OreType, amount: float)

## Units carried per ore type, in the order they first arrived; emptied ones stay at zero until
## `take_all`.
var ores: Dictionary[OreType, float] = {}


## Units of `ore_type` carried.
func amount(ore_type: OreType) -> float:
	return ores.get(ore_type, 0.0)


## Units carried of all ore types together.
func total() -> float:
	var units: float = 0.0
	for carried: float in ores.values():
		units += carried
	return units


## Whether it carries nothing.
func is_empty() -> bool:
	return total() <= 0.0


## Adds `units` of `ore_type`.
func add(ore_type: OreType, units: float) -> void:
	if units <= 0.0:
		return
	var carried: float = amount(ore_type) + units
	ores[ore_type] = carried
	ore_changed.emit(ore_type, carried)
	ore_added.emit(ore_type, units)


## Takes up to `units` of `ore_type` out (e.g. made into ammo). Returns what it took.
func take(ore_type: OreType, units: float) -> float:
	var carried: float = amount(ore_type)
	if units <= 0.0 or carried <= 0.0:
		return 0.0
	var left: float = maxf(carried - units, 0.0)
	if left < 0.0001:
		left = 0.0
	ores[ore_type] = left
	ore_changed.emit(ore_type, left)
	return carried - left


## Takes everything out and returns it.
func take_all() -> Dictionary[OreType, float]:
	var taken: Dictionary[OreType, float] = ores
	ores = {}
	for ore_type: OreType in taken:
		ore_changed.emit(ore_type, 0.0)
	return taken
