class_name DrillTrigger
extends WeaponTrigger
## Press to thrust, hold on to drill (Auger): a press attacks once (a thrust, see
## `ThrustDelivery`); held on after a thrust that latched on to an alien or a nest
## (`Weapon.latched`), it keeps attacking (drilling) while the latch holds. The bit spins while the
## button is held (`Weapon.wind`): at `idle_spin` of its speed, up to full with a thrust and with
## the drill's ramp; let go, it spins down within `spin_down`. The holder walks slower while it
## drills. A loop plays while the bit spins, its pitch following it. All values TBD (playtest).

## Share of the holder's top speed while it drills.
@export_range(0.0, 1.0) var drilling_move_share: float = 0.4
## Share of its full speed the bit spins at while the button is held and it isn't drilling.
@export_range(0.0, 1.0) var idle_spin: float = 0.5
## Seconds the bit takes to spin up from still to `idle_spin`, and down from full speed.
@export var spin_up: float = 0.15
@export var spin_down: float = 0.6

@export_group("Sounds")
## The drill running and grinding (a loop).
@export var drill_sound: Sound


func update(weapon: Weapon, delta: float, able: bool, pressed: bool) -> bool:
	if pressed and able:
		weapon.latch(null)
		return true
	var drilling: bool = (
		weapon.trigger_held and is_instance_valid(weapon.latched) and weapon.is_drawn()
	)
	if not drilling:
		weapon.latch(null)
		var spin: float = idle_spin if weapon.trigger_held and weapon.is_drawn() else 0.0
		if weapon.wind < spin:
			weapon.wind = minf(weapon.wind + delta * spin / maxf(spin_up, 0.01), spin)
		else:
			weapon.wind = maxf(weapon.wind - delta / maxf(spin_down, 0.01), spin)
	if weapon.wind > 0.0:
		weapon.hold_loop(drill_sound, lerpf(0.6, 1.3, weapon.wind))
	else:
		weapon.stop_loop()
	return drilling


func move_share(weapon: Weapon) -> float:
	return drilling_move_share if is_instance_valid(weapon.latched) else 1.0
