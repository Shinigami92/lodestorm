class_name UpgradeLevel
extends Resource
## One MK level of an upgrade beyond MK1: what it costs and how much it improves. Values TBD
## (playtest).

## Ore taken from the ship's hold for this level, in units per ore type.
@export var cost: Dictionary[OreType, int] = {}
## The improved values compared to MK1 (e.g. 1.25: 25 % more damage).
@export var multiplier: float = 1.0
