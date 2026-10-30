class_name OreAmmo
## The suit's ammo maker: ranged weapons pay their rounds with carried ore (see
## `WeaponFeed.ore_per_round`). Any ore type works, each worth its `OreType.ammo_yield`;
## the commonest one (lowest `OreType.tier`) is used first, so rare ore is spent last.

## Rounds `affordable` reports when they cost nothing.
const MAX_ROUNDS: int = 1 << 30


## What `cargo` is worth as ammo: units weighted by their ammo yield.
static func value(cargo: Dictionary[OreType, float]) -> float:
	var total: float = 0.0
	for ore_type: OreType in cargo:
		total += cargo[ore_type] * ore_type.ammo_yield
	return total


## How many rounds `cargo` pays at `ore_per_round` each.
static func affordable(cargo: Dictionary[OreType, float], ore_per_round: float) -> int:
	if ore_per_round <= 0.0:
		return MAX_ROUNDS
	# A little tolerance, so float rounding never loses a round that was paid in full.
	return floori(value(cargo) / ore_per_round + 0.0001)


## Takes ore worth `amount` (see `value`) from what `player` carries, the commonest first.
static func spend(player: Player, amount: float) -> void:
	for ore_type: OreType in _commonest_first(player.cargo.ores):
		if amount <= 0.0:
			break
		var used: float = player.cargo.take(ore_type, amount / ore_type.ammo_yield)
		amount -= used * ore_type.ammo_yield
		GameEvents.bus.ammo_paid.emit(player, ore_type, used)


## The units of each ore in `cargo` that `spend` would take first for ammo worth `worth`: the
## commonest first, all of what's carried if it's worth less.
static func reserve(cargo: Dictionary[OreType, float], worth: float) -> Dictionary[OreType, float]:
	var kept: Dictionary[OreType, float] = {}
	for ore_type: OreType in _commonest_first(cargo):
		if worth <= 0.0:
			break
		var units: float = minf(cargo[ore_type], worth / ore_type.ammo_yield)
		if units <= 0.0:
			continue
		kept[ore_type] = units
		worth -= units * ore_type.ammo_yield
	return kept


static func _commonest_first(cargo: Dictionary[OreType, float]) -> Array[OreType]:
	var ore_types: Array[OreType] = cargo.keys()
	ore_types.sort_custom(func(a: OreType, b: OreType) -> bool: return a.tier < b.tier)
	return ore_types
