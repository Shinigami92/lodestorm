class_name OreExchange
extends RefCounted
## The ore exchange at Waypost Ostra's depot (see docs/design/station.md): a safety valve at a
## bad rate. Any ore in the player's hold goes in, `RATE` units for each unit of another ore that
## comes out; what comes out is a common or mid ore the hold ever had (signature ores can be traded
## away but never bought, so a planet's signature ore is still mined there, and ores never found
## stay unknown). Paid from the player's own hold, at once.

## Units going in for each unit coming out. TBD (playtest).
const RATE: int = 3


## Whether `ore` can go in: the hold has `RATE` units of it at least.
static func can_put_in(ore: OreType, hold: PlayerHold) -> bool:
	return ore != null and hold.amount(ore) >= RATE


## Whether `ore` can come out: a common or mid ore the hold ever had.
static func can_take_out(ore: OreType, hold: PlayerHold) -> bool:
	return ore != null and ore.band != OreType.Band.SIGNATURE and hold.has_found(ore)


## The ores that can go in, commonest first.
static func ores_in(hold: PlayerHold) -> Array[OreType]:
	var result: Array[OreType] = []
	for ore: OreType in OreCatalog.all().ores:
		if can_put_in(ore, hold):
			result.append(ore)
	return result


## The ores that can come out, commonest first.
static func ores_out(hold: PlayerHold) -> Array[OreType]:
	var result: Array[OreType] = []
	for ore: OreType in OreCatalog.all().ores:
		if can_take_out(ore, hold):
			result.append(ore)
	return result


## How many units of another ore `ore_in` pays for from `hold`.
static func affordable(ore_in: OreType, hold: PlayerHold) -> int:
	return floori(hold.amount(ore_in) / RATE) if ore_in else 0


## What `count` units out cost: `RATE` times as much of `ore_in`.
static func cost(ore_in: OreType, count: int) -> Dictionary[ItemType, int]:
	var result: Dictionary[ItemType, int] = {}
	result[ore_in] = count * RATE
	return result


## Whether `count` units of `ore_out` can be had for `ore_in` from `hold` now.
static func can_trade(ore_in: OreType, ore_out: OreType, count: int, hold: PlayerHold) -> bool:
	return (
		count > 0
		and ore_in != ore_out
		and can_put_in(ore_in, hold)
		and can_take_out(ore_out, hold)
		and count <= affordable(ore_in, hold)
	)


## Trades `count` units of `ore_out` for `count * RATE` units of `ore_in`, in `hold`. Returns
## whether it did.
static func trade(ore_in: OreType, ore_out: OreType, count: int, hold: PlayerHold) -> bool:
	if not can_trade(ore_in, ore_out, count, hold) or not hold.pay(cost(ore_in, count)):
		return false
	hold.add(ore_out, count)
	return true
