class_name MinerSettings
extends Resource
## Miner tuning values (later upgradable / per miner type). All values TBD (playtest); target:
## an empty miner takes about 2–5 min to fill (`capacity / fill_rate`).

## Units mined per second.
@export var fill_rate: float = 1.0
## Units a miner holds; it stops mining when full.
@export var capacity: float = 180.0
## How close (horizontally, in m) a player must be for the hose to connect.
@export var hose_range: float = 5.0
## Units per second the hose moves from the miner to the player.
@export var transfer_rate: float = 30.0
