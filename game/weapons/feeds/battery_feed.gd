class_name BatteryFeed
extends WeaponFeed
## A weapon fed by a battery that recharges by itself, for no ore (Pinner), see `BatteryAmmo`.
## All values TBD (playtest).

## Shots a full battery holds at MK1.
@export var cells: int = 12
## Seconds after the last shot until it starts recharging.
@export var recharge_delay: float = 0.8
## Shots it recharges per second at MK1 (more with the MK level of the weapon's recharge).
@export var recharge_rate: float = 5.0
## Seconds from drained to full at MK1, when it ran empty (it can't fire meanwhile).
@export var drained_recharge_time: float = 2.5

@export_group("Sounds")
## Full again after running empty.
@export var charged_sound: Sound


func _init() -> void:
	ore_per_round = 0.0


func create_ammo(weapon: Weapon) -> WeaponAmmo:
	return BatteryAmmo.new(weapon, self)
