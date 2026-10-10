class_name Loadout
extends Resource
## The weapons a player takes into a mission, picked from all available ones before it starts.
## Number of slots and switching weapons during a mission: TBD (playtest).

## Weapon scenes (root extends `Weapon`), in slot order.
@export var weapons: Array[PackedScene] = []
