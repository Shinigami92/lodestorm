class_name OreAmmo
## The suit's ammo maker: ranged weapons pay their rounds with carried ore (see
## `RangedWeaponSettings.ore_per_round`). Any ore type works, each worth its `OreType.ammo_yield`;
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
	var ore_types: Array[OreType] = player.cargo.keys()
	ore_types.sort_custom(func(a: OreType, b: OreType) -> bool: return a.tier < b.tier)
	for ore_type: OreType in ore_types:
		if amount <= 0.0:
			break
		var used: float = minf(player.cargo[ore_type], amount / ore_type.ammo_yield)
		amount -= used * ore_type.ammo_yield
		player.take_ore(ore_type, used)
