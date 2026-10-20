class_name FieldFeed
extends WeaponFeed
## A shield's field (Mantle), see `FieldAmmo`: not ammo (its bash needs none) but the charge its
## field blocks with, recharging by itself for no ore. All values TBD (playtest).

## Damage a full field stops at MK1.
@export var charge: int = 100
## Seconds after the last block until it starts recharging.
@export var recharge_delay: float = 1.5
## Charge it recharges per second.
@export var recharge_rate: float = 25.0
## Seconds a broken field stays down before it's back full.
@export var break_time: float = 3.0

@export_group("Sounds")
## The field breaking, and coming back.
@export var break_sound: Sound
@export var back_sound: Sound


func _init() -> void:
	ore_per_round = 0.0


func create_ammo(weapon: Weapon) -> WeaponAmmo:
	return FieldAmmo.new(weapon, self)


func is_ammo() -> bool:
	return false
