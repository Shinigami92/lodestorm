class_name UpgradeLevel
extends Resource
## One MK level of an upgrade beyond MK1: how much it improves. What it costs is the same rule for
## every upgrade (see `MkCosts`). Values TBD (playtest).

## The improved values compared to MK1 (e.g. 1.25: 25 % more damage).
@export var multiplier: float = 1.0
