class_name ShieldPlate
extends Resource
## One plate of the ship's heat shield beyond MK1: what it costs (see `HeatShield`). Values TBD
## (playtest).

## Ore paid into the plate, in units per ore type (ores only, never alloys).
@export var cost: Dictionary[OreType, int] = {}
