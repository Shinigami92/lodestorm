class_name Loadout
extends Resource
## The weapons a player takes into a mission, picked from the ones they own in the armory before it
## starts. Each slot holds one weapon or none; a weapon is in one slot at most. Number of slots
## (`PlayerSettings.loadout_slots`): TBD (playtest).

## Weapon per slot (null: empty), in slot order. Slots past its end are empty.
@export var weapons: Array[WeaponType] = []


## The weapon in `slot`, or null.
func get_weapon(slot: int) -> WeaponType:
	return weapons[slot] if slot >= 0 and slot < weapons.size() else null


## The slot holding `weapon_type`, or -1.
func slot_of(weapon_type: WeaponType) -> int:
	return weapons.find(weapon_type) if weapon_type else -1


## Puts `weapon_type` into `slot` (null empties it). When the weapon is in another slot already,
## the two slots swap.
func assign(slot: int, weapon_type: WeaponType) -> void:
	while weapons.size() <= slot:
		weapons.append(null)
	var previous: WeaponType = weapons[slot]
	var other: int = slot_of(weapon_type)
	if other != -1 and other != slot:
		weapons[other] = previous
	weapons[slot] = weapon_type
	emit_changed()


## What's saved: the weapon per slot (null: empty).
func save_data() -> Array:
	var saved: Array = []
	for weapon_type: WeaponType in weapons:
		if weapon_type:
			saved.append(SaveData.uid_of(weapon_type))
		else:
			saved.append(null)
	return saved


## Reads the slots a save has (`save_data`), only with weapons `arsenal` owns (anything else leaves
## the slot empty). The locker never empties the loadout, so a save that does is damaged: the
## default slots stay, without weapons not owned. Returns whether all of it read.
func load_data(saved: Variant, arsenal: Arsenal) -> bool:
	if saved == null:
		return true
	if not saved is Array:
		return SaveData.skipped("loadout", saved)
	var slots: Array[WeaponType] = []
	for entry: Variant in saved as Array:
		var weapon_type := SaveData.load_uid(entry, WeaponType) as WeaponType
		slots.append(weapon_type if weapon_type and arsenal.owns(weapon_type) else null)
	if slots.any(func(weapon_type: WeaponType) -> bool: return weapon_type != null):
		for slot: int in slots.size():
			assign(slot, slots[slot])
		return true
	for slot: int in weapons.size():
		if not arsenal.owns(get_weapon(slot)):
			assign(slot, null)
	return SaveData.skipped("loadout without an owned weapon", saved)
