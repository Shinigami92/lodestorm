class_name ChargeTrigger
extends WeaponTrigger
## Hold to charge, let go to attack (Quill): holding the attack button charges the next attack
## (`Weapon.wind` from 0 to 1 within `charge_time`, quicker with the MK level of the weapon's
## charge) while it could attack; letting go makes it with `Weapon.power` from `min_power` to 1 by
## the charge (a full charge pierces with `ProjectileDelivery.pierce`). A hum rises while it
## charges, a ping says it's full. All values TBD (playtest).

## Seconds to a full charge at MK1.
@export var charge_time: float = 1.2
## Power of an attack let go right away, as a share of a full charge's.
@export_range(0.0, 1.0) var min_power: float = 0.3
## Share of the holder's top speed while it charges.
@export_range(0.0, 1.0) var charging_move_share: float = 1.0

@export_group("Sounds")
## The charge building up (a loop), its pitch rising with the charge.
@export var charge_sound: Sound
## The charge becoming full.
@export var full_sound: Sound


func update(weapon: Weapon, delta: float, able: bool, _pressed: bool) -> bool:
	if weapon.trigger_held:
		if able:
			var rate: float = weapon.multiplier(WeaponPart.Stat.CHARGE) / maxf(charge_time, 0.01)
			var was_full: bool = weapon.wind >= 1.0
			weapon.wind = minf(weapon.wind + delta * rate, 1.0)
			weapon.hold_loop(charge_sound, lerpf(0.7, 1.3, weapon.wind))
			if weapon.wind >= 1.0 and not was_full:
				weapon.play(full_sound)
		return false
	if weapon.wind <= 0.0:
		return false
	weapon.power = lerpf(min_power, 1.0, weapon.wind)
	weapon.wind = 0.0
	weapon.stop_loop()
	return able


func charge(weapon: Weapon) -> float:
	return weapon.wind


func move_share(weapon: Weapon) -> float:
	return charging_move_share if weapon.wind > 0.0 else 1.0
