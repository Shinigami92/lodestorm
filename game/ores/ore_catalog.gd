class_name OreCatalog
extends Resource
## Every ore of the game, commonest first (by `OreType.tier`): `game/ores/all_ores.tres`.
## The hold's tanks, the debug fills and the tests go through it, so a new ore only needs its
## resource and an entry here.

const ALL_PATH: String = "res://game/ores/all_ores.tres"

@export var ores: Array[OreType] = []


## The catalog of every ore.
static func all() -> OreCatalog:
	return load(ALL_PATH) as OreCatalog


## `ore_types` ordered commonest first (by tier).
static func sorted(ore_types: Array[OreType]) -> Array[OreType]:
	var result: Array[OreType] = ore_types.duplicate()
	result.sort_custom(func(a: OreType, b: OreType) -> bool: return a.tier < b.tier)
	return result
