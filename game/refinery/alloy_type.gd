class_name AlloyType
extends ItemType
## An alloy the refinery's furnaces make from ores (see `FurnaceStation`): an item (`ItemType`)
## whose shape is an ingot, with 1–4 stamped ticks for its tier on its badge. Every alloy of the
## game is listed in `game/refinery/all_alloys.tres` (`AlloyCatalog`), by tier. Its recipe shows
## once every ore in it was in the player's hold (`is_known`).

## The ingot icons drawn per tier.
static var _ingots: Dictionary[int, Texture2D] = {}

## 1–4: which upgrade levels it goes into (from M4 step 11 D) and how long a bar takes.
@export var tier: int = 1
## Units of each ore one bar takes: the common ore as bulk, a mid ore and from tier 2 on the
## signature ore. TBD (playtest).
@export var recipe: Dictionary[OreType, int] = {}
## Seconds a furnace takes for one bar, on the wall clock. TBD (playtest).
@export var seconds_per_bar: float = 60.0


## What `bars` bars take, in units per item (ores).
func cost(bars: int) -> Dictionary[ItemType, int]:
	var total: Dictionary[ItemType, int] = {}
	for ore_type: OreType in recipe:
		total[ore_type] = recipe[ore_type] * bars
	return total


## How many bars `hold` pays for.
func affordable(hold: PlayerHold) -> int:
	var bars: int = -1
	for ore_type: OreType in recipe:
		var most: int = floori(hold.amount(ore_type) / recipe[ore_type])
		bars = most if bars < 0 else mini(bars, most)
	return maxi(bars, 0)


## Whether its recipe shows: every ore in it was in `hold` at some point.
func is_known(hold: PlayerHold) -> bool:
	for ore_type: OreType in recipe:
		if not hold.has_found(ore_type):
			return false
	return true


## The ores of its recipe `hold` has found so far (what an unknown recipe shows).
func found_ores(hold: PlayerHold) -> Array[OreType]:
	var found: Array[OreType] = []
	for ore_type: OreType in recipe:
		if hold.has_found(ore_type):
			found.append(ore_type)
	return found


## Its `icon`, else an ingot with its tier's ticks drawn in code.
func get_badge_icon() -> Texture2D:
	if icon:
		return icon
	if not _ingots.has(tier):
		_ingots[tier] = IngotIcon.draw(tier)
	return _ingots[tier]
