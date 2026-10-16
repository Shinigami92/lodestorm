class_name Arsenal
extends Resource
## The weapons a player owns. A new player starts with a few; the others are unlocked through the
## game (blueprints from quests and the story). The loadout is picked from them.
## `game/weapons/all_weapons.tres` is the arsenal with every weapon in the game, in the order the
## armory lists them.

@export var weapons: Array[WeaponType] = []


func owns(weapon_type: WeaponType) -> bool:
	return weapon_type in weapons


## Adds `weapon_type` unless it's owned already. Returns whether it was new.
func unlock(weapon_type: WeaponType) -> bool:
	if not weapon_type or owns(weapon_type):
		return false
	weapons.append(weapon_type)
	emit_changed()
	return true
