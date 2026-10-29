class_name Arsenal
extends Resource
## The weapons a player owns (`weapons`) and the blueprints they have (`blueprints`). A new player
## starts with a few weapons; the others come as blueprints (from quests and the story) and are
## built at the workbench for ore (`WeaponStation.build`). The loadout is picked from the owned
## ones. `game/weapons/all_weapons.tres` is the arsenal with every weapon in the game, in the order
## the armory lists them.

## Emitted when a weapon is added (built, or a debug shortcut), or a blueprint found.
signal unlocked(weapon_type: WeaponType)
signal learned(weapon_type: WeaponType)

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
	learned.emit(weapon_type)
	return true


## Adds `weapon_type` unless it's owned already (built, or a debug shortcut); its blueprint is used
## up. Returns whether it was new.
func unlock(weapon_type: WeaponType) -> bool:
	if not weapon_type or owns(weapon_type):
		return false
	weapons.append(weapon_type)
	blueprints.erase(weapon_type)
	emit_changed()
	unlocked.emit(weapon_type)
	return true


## What's saved: the weapons owned and the blueprints, in their order.
func save_data() -> Dictionary:
	return {"weapons": SaveData.uids_of(weapons), "blueprints": SaveData.uids_of(blueprints)}


## Reads what a save has (`save_data`). Weapons are never taken away, so a save without a known
## one is damaged: the default ones stay. Returns whether all of it read.
func load_data(saved: Variant) -> bool:
	if saved == null:
		return true
	var data: Dictionary = saved if saved is Dictionary else {}
	var saved_weapons: Variant = data.get("weapons", [])
	var saved_blueprints: Variant = data.get("blueprints", [])
	if not saved is Dictionary or not saved_weapons is Array or not saved_blueprints is Array:
		return SaveData.skipped("arsenal", saved)
	var listed: Array = saved_weapons
	var owned: Array[WeaponType] = []
	for weapon_type: WeaponType in SaveData.load_uids(listed, WeaponType, "weapon"):
		if weapon_type not in owned:
			owned.append(weapon_type)
	var complete: bool = owned.size() == listed.size()
	if owned.is_empty():
		complete = SaveData.skipped("arsenal without a known weapon", saved_weapons)
	else:
		weapons = owned
	listed = saved_blueprints
	var known: Array[WeaponType] = []
	for weapon_type: WeaponType in SaveData.load_uids(listed, WeaponType, "blueprint"):
		if weapon_type not in known and not owns(weapon_type):
			known.append(weapon_type)
	blueprints = known
	emit_changed()
	return complete and known.size() == listed.size()
