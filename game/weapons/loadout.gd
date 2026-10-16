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
