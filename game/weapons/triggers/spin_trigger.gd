class_name SpinTrigger
extends WeaponTrigger
## Barrels that spin up before the first shot (Grindle): holding the attack button spins them up
## (`Weapon.wind` from 0 to 1, quicker with the MK level of the weapon's spin-up), then it attacks
## at its rate while held. Let go, they keep spinning for a moment, so a quick press fires at once,
## then spin down. The holder walks slower while they spin. A loop plays meanwhile, its pitch
## following the spin. All values TBD (playtest).

## Seconds from still to full speed at MK1.
@export var spin_up: float = 0.6
## Seconds the barrels keep full speed after the button is let go.
@export var keep_spinning: float = 1.0
## Seconds from full speed to still after that.
@export var spin_down: float = 0.6
## Share of the holder's top speed while they spin at full speed.
@export_range(0.0, 1.0) var spinning_move_share: float = 0.6

@export_group("Sounds")
## The barrels spinning (a loop), from half its pitch when still to its pitch at full speed.
@export var spin_sound: Sound


func update(weapon: Weapon, delta: float, _ready: bool, _pressed: bool) -> bool:
	if weapon.trigger_held and weapon.is_drawn():
		var rate: float = weapon.multiplier(WeaponPart.Stat.SPIN) / maxf(spin_up, 0.01)
		weapon.wind = minf(weapon.wind + delta * rate, 1.0)
	elif weapon.released_for > keep_spinning:
		weapon.wind = maxf(weapon.wind - delta / maxf(spin_down, 0.01), 0.0)
	if weapon.wind > 0.0:
		weapon.hold_loop(spin_sound, lerpf(0.5, 1.0, weapon.wind))
	else:
		weapon.stop_loop()
	return weapon.trigger_held and weapon.wind >= 1.0


func move_share(weapon: Weapon) -> float:
	return lerpf(1.0, spinning_move_share, weapon.wind)
