class_name PressTrigger
extends WeaponTrigger
## One attack per press of the attack button (semi-automatic, Pinner), at most at the weapon's
## attack rate: a press before the time between attacks is over does nothing.


func update(_weapon: Weapon, _delta: float, _ready: bool, pressed: bool) -> bool:
	return pressed
