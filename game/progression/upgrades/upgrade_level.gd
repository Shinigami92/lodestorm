class_name UpgradeLevel
extends Resource
## One MK level of an upgrade beyond MK1: how much it improves and how long it takes. What it costs
## is the same rule for every upgrade (see `MkCosts`). Values TBD (playtest).

## The improved values compared to MK1 (e.g. 1.25: 25 % more damage).
@export var multiplier: float = 1.0
## How long reaching it takes on the wall clock once paid, in seconds (see `Upgrades.start`).
@export var seconds: float = 0.0
## Drills only: the hardest ore (`OreType.hardness`) it mines at full speed.
@export var hardness: int = 0
