class_name ShieldPlate
extends Resource
## One plate of the ship's heat shield beyond MK1: what it costs (see `HeatShield`). Values TBD
## (playtest).

## Ore paid into the plate, in units per ore type (ores only, never alloys).
@export var cost: Dictionary[OreType, int] = {}
## Whether it can only become the ship's project once the whole crew is aboard
## (`NpcProfile.whole_crew_aboard`): MK2 (Vehra), the only gate besides the heat shield itself.
@export var needs_whole_crew: bool = false
