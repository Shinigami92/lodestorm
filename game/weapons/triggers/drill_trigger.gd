class_name DrillTrigger
extends WeaponTrigger
## Press to thrust, hold on to drill (Auger): a press attacks once (a thrust, see
## `ThrustDelivery`); held on after a thrust that latched on to an alien or a nest
## (`Weapon.latched`), it keeps attacking (drilling) while the latch holds. Letting go ends the
## drill, and the bit spins down within `spin_down`. The holder walks slower while it drills, and a
## loop plays, its pitch rising with the drill's ramp (`Weapon.wind`). All values TBD (playtest).

## Share of the holder's top speed while it drills.
@export_range(0.0, 1.0) var drilling_move_share: float = 0.4
## Seconds the bit takes to spin down from full speed when it isn't drilling.
@export var spin_down: float = 0.6

@export_group("Sounds")
## The drill grinding (a loop).
@export var drill_sound: Sound


func update(weapon: Weapon, delta: float, able: bool, pressed: bool) -> bool:
	if pressed and able:
		weapon.latch(null)
		weapon.stop_loop()
		return true
	if not weapon.trigger_held or not is_instance_valid(weapon.latched):
		weapon.latch(null)
		weapon.wind = maxf(weapon.wind - delta / maxf(spin_down, 0.01), 0.0)
	elif weapon.is_drawn():
		weapon.hold_loop(drill_sound, lerpf(0.8, 1.3, weapon.wind))
		return true
	weapon.stop_loop()
	return false


func move_share(weapon: Weapon) -> float:
	return drilling_move_share if is_instance_valid(weapon.latched) else 1.0
