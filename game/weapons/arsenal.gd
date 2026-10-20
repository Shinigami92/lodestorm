class_name Arsenal
extends Resource
## The weapons a player owns (`weapons`) and the blueprints they have (`blueprints`). A new player
## starts with a few weapons; the others come as blueprints (from quests and the story) and are
## built at the workbench for ore (`WeaponStation.build`). The loadout is picked from the owned
## ones. `game/weapons/all_weapons.tres` is the arsenal with every weapon in the game, in the order
## the armory lists them.

@export var weapons: Array[WeaponType] = []
## Blueprints of weapons not built yet.
@export var blueprints: Array[WeaponType] = []


func owns(weapon_type: WeaponType) -> bool:
	return weapon_type in weapons


## Whether `weapon_type` can be built: its blueprint is there and it isn't owned yet.
func has_blueprint(weapon_type: WeaponType) -> bool:
	return weapon_type in blueprints and not owns(weapon_type)


## Adds the blueprint of `weapon_type` unless it's owned or known already. Returns whether it was
## new.
func learn(weapon_type: WeaponType) -> bool:
	if not weapon_type or owns(weapon_type) or weapon_type in blueprints:
		return false
	blueprints.append(weapon_type)
	emit_changed()
	return true


## Adds `weapon_type` unless it's owned already (built, or a debug shortcut); its blueprint is used
## up. Returns whether it was new.
func unlock(weapon_type: WeaponType) -> bool:
	if not weapon_type or owns(weapon_type):
		return false
	weapons.append(weapon_type)
	blueprints.erase(weapon_type)
	emit_changed()
	return true
