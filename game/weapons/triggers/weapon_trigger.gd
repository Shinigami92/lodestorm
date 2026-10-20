@abstract class_name WeaponTrigger
extends Resource
## How holding the attack button makes a weapon attack (see `WeaponType.trigger`); a weapon
## without one attacks at its rate while the button is held. So far one attack per press
## (`PressTrigger`), barrels or a blade spinning up before the first attack (`SpinTrigger`), a
## charge let go as one stronger attack (`ChargeTrigger`) and a press to thrust, held on to drill
## (`DrillTrigger`). What it winds up lives on the weapon (`Weapon.wind`).
## All values TBD (playtest).

## Called every physics frame of `weapon`: whether it attacks now, if it can (`able`: drawn, the
## time between attacks over, a round loaded). `pressed`: the button went down this frame.
@abstract func update(weapon: Weapon, delta: float, able: bool, pressed: bool) -> bool


## Share of the holder's top speed while it's used.
func move_share(_weapon: Weapon) -> float:
	return 1.0


## How far the attack being charged is, 0 to 1 (shown on the suit ring); 0 when it doesn't charge.
func charge(_weapon: Weapon) -> float:
	return 0.0
