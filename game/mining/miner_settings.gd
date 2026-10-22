class_name MinerSettings
extends Resource
## Miner tuning values (raised per crafted miner by its parts' levels) and what building one costs.
## All values TBD (playtest); target:
## an empty miner takes about 2–5 min to fill (`capacity / fill_rate`).

## Units mined per second.
@export var fill_rate: float = 1.0
## Units a miner holds; it stops mining when full.
@export var capacity: float = 180.0
## How close (horizontally, in m) a player must be for the hose to connect.
@export var hose_range: float = 5.0
## Units per second the hose moves from the miner to the player.
@export var transfer_rate: float = 30.0
## Health of an undamaged miner; it breaks down at zero.
@export var max_health: float = 100.0
## Health per second a player standing next to the miner repairs.
@export var repair_rate: float = 25.0
## How close (horizontally, in m) a player must be to repair the miner.
@export var repair_range: float = 2.5
## Seconds a player takes to place a miner and to pick one up (standing still meanwhile).
@export var place_time: float = 3.0
@export var pick_up_time: float = 5.0
## Share of the fill rate a standard-issue miner mines at (the ship's, never upgraded).
@export var standard_fill_share: float = 0.75
## Share of the fill rate a miner mines an ore at that's harder than its drill mines at full speed
## (`OreType.hardness`, `Upgrade.hardness_at`).
@export var soft_drill_share: float = 0.25
## What building a crafted miner costs, in units per item (ores and alloys); the same for every
## cradle, also for one built again after it was lost.
@export var build_cost: Dictionary[ItemType, int] = {}
## How long building a crafted miner takes, in seconds on the wall clock.
@export var build_seconds: int = 180


## How fast `ore_type` mines compared to the commonest ore with a drill that mines up to
## `drill_hardness` at full speed: its own rate, slowed further when it's harder than that.
func ore_share(ore_type: OreType, drill_hardness: int) -> float:
	if not ore_type:
		return 1.0
	var soft: bool = ore_type.hardness > drill_hardness
	return ore_type.mine_rate * (soft_drill_share if soft else 1.0)
