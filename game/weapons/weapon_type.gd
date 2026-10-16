class_name WeaponType
extends Resource
## One weapon of the game as the armory lists it: its name, how it plays and its scene. Players
## own weapon types (`Arsenal`) and take some into a mission (`Loadout`).

enum Kind { RANGED, MELEE }

## Player-facing name.
@export var display_name: String = ""
## One line on how it plays, shown in the armory.
@export var description: String = ""
@export var kind: Kind = Kind.RANGED
## The weapon scene (root extends `Weapon`).
@export var scene: PackedScene
## Its MK levels at the weapons upgrade station: each one raises its damage.
@export var upgrade: Upgrade
## The MK levels of its magazine (ranged weapons): each one holds more rounds.
@export var magazine_upgrade: Upgrade


## Its upgrades (the parts the weapons upgrade station improves), in the order the station lists
## them.
func get_upgrades() -> Array[Upgrade]:
	var parts: Array[Upgrade] = []
	for part: Upgrade in [upgrade, magazine_upgrade]:
		if part:
			parts.append(part)
	return parts
