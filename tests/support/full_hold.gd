extends RefCounted
## A hold with plenty of every ore and alloy, for tests that start jobs or builds without testing
## what they cost.

const PLENTY: float = 1.0e6


## `hold` (a new one for null) with `PLENTY` more of every ore and alloy.
static func fill(hold: PlayerHold = null) -> PlayerHold:
	var full: PlayerHold = hold if hold else PlayerHold.new()
	for ore_type: OreType in OreCatalog.all().ores:
		full.add(ore_type, PLENTY)
	for alloy: AlloyType in AlloyCatalog.all().alloys:
		full.add(alloy, PLENTY)
	return full
