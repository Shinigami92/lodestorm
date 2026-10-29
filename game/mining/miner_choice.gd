class_name MinerChoice
extends RefCounted
## One of a player's miners still to place in a run, as placing chooses between them (see
## docs/design/mining.md): a crafted one (`crafted`) or a standard-issue one (null). `options`
## lists them, `default_for` picks the one placing takes unless the player steps to another (see
## `MinerPicker`): the softest drill that still mines the ore at full speed (a standard-issue one
## before a crafted one with the same drill level, crafted ones by number), so the better drills
## stay free for harder ore; without one at full speed, the fastest.

const SETTINGS: MinerSettings = preload("res://game/mining/miner_settings.tres")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const TANK: Upgrade = preload("res://game/progression/upgrades/miner_tank.tres")

## The crafted miner, or null: a standard-issue one.
var crafted: CraftedMiner


func _init(miner: CraftedMiner = null) -> void:
	crafted = miner


func is_standard() -> bool:
	return crafted == null


## Whether it's the same miner as `other`.
func same_as(other: MinerChoice) -> bool:
	return other != null and other.crafted == crafted


## Its drill's MK level (standard-issue ones MK1).
func drill_mk() -> int:
	return crafted.upgrades.mk(DRILL) if crafted else 1


## Its tank's MK level (standard-issue ones MK1).
func tank_mk() -> int:
	return crafted.upgrades.mk(TANK) if crafted else 1


## Whether its drill mines `ore_type` at full speed (see `Upgrade.hardness_at`).
func full_speed(ore_type: OreType) -> bool:
	return not ore_type or ore_type.hardness <= DRILL.hardness_at(drill_mk())


## Units it would mine per second on `ore_type`.
func fill_rate(ore_type: OreType) -> float:
	return rate(SETTINGS, DRILL, ore_type, crafted.upgrades if crafted else null, is_standard())


## Seconds it would take to fill on `node` (or until the node runs dry, if it holds less).
func fill_time(node: OreNode) -> float:
	var capacity: float = (
		SETTINGS.capacity * (crafted.upgrades.multiplier(TANK) if crafted else 1.0)
	)
	var mined: float = minf(capacity, node.amount if node.amount >= 0.0 else capacity)
	var per_second: float = fill_rate(node.ore_type)
	return mined / per_second if per_second > 0.0 else INF


## The miners still to place in `fleet`'s run: its crafted ones by number, then a standard-issue
## one while any are left.
static func options(fleet: MinerFleet) -> Array[MinerChoice]:
	var result: Array[MinerChoice] = []
	for miner: CraftedMiner in fleet.waiting():
		result.append(MinerChoice.new(miner))
	if fleet.standard_left() > 0:
		result.append(MinerChoice.new())
	return result


## The miner placing takes on an ore node of `ore_type` without a choice, or null when none is left.
static func default_for(fleet: MinerFleet, ore_type: OreType) -> MinerChoice:
	var all: Array[MinerChoice] = options(fleet)
	if all.is_empty():
		return null
	# A standard-issue one first, so it wins a tie of drill levels.
	var softest_first: Array[MinerChoice] = all.duplicate()
	if softest_first[-1].is_standard():
		softest_first.push_front(softest_first.pop_back())
	var best: MinerChoice = null
	for choice: MinerChoice in softest_first:
		if choice.full_speed(ore_type) and (not best or choice.drill_mk() < best.drill_mk()):
			best = choice
	if best:
		return best
	var best_rate: float = -1.0
	for choice: MinerChoice in all:
		var choice_rate: float = choice.fill_rate(ore_type)
		if choice_rate > best_rate:
			best = choice
			best_rate = choice_rate
	return best


## Units per second a miner with `settings` and the drill `drill` at the MK level of `levels`
## (null: MK1) mines `ore_type` at; `standard_issue`: at the ship's share. Rarer ores mine slower
## (`OreType.mine_rate`), and ores too hard for the drill slower still.
static func rate(
	settings: MinerSettings,
	drill: Upgrade,
	ore_type: OreType,
	levels: Upgrades,
	standard_issue: bool
) -> float:
	var share: float = settings.standard_fill_share if standard_issue else 1.0
	var mk: int = levels.mk(drill) if levels else 1
	var multiplier: float = levels.multiplier(drill) if levels else 1.0
	return (
		settings.fill_rate
		* share
		* multiplier
		* settings.ore_share(ore_type, drill.hardness_at(mk))
	)
