class_name AlloyCatalog
extends Resource
## Every alloy of the game, by tier (`AlloyType.tier`): `game/refinery/all_alloys.tres`. The
## furnaces' recipes, the ingot rack's shelves, the debug fills and the tests go through it, so a
## new alloy only needs its resource and an entry here.

const ALL_PATH: String = "res://game/refinery/all_alloys.tres"

@export var alloys: Array[AlloyType] = []


## The catalog of every alloy.
static func all() -> AlloyCatalog:
	return load(ALL_PATH) as AlloyCatalog
