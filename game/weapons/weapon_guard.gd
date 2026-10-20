class_name WeaponGuard
extends Resource
## A shield's guard (Mantle, see `WeaponType.guard`): while the weapon is drawn, a field stands in
## front of its holder (`ShieldField`) and blocks what comes at them from within its arc (wider
## with the MK level of the weapon's arc): every blow of an alien, and alien shots crossing it
## whoever they were aimed at, draining its charge (its `FieldFeed`). Heavy blows (a charge, a
## slam) also shove the holder back, and a charge stopped by it leaves the charger dazed. Right
## after a bash (`open_after` seconds from the attack, for `open_time`) it doesn't block: the arm
## comes back. The holder walks a little slower with it. All values TBD (playtest).

## Width of the field around where the holder faces at MK1, in degrees.
@export var arc: float = 120.0
## How far in front of the holder's middle the field stands, and how high it reaches (m).
@export var radius: float = 1.1
@export var height: float = 2.2
## Seconds after a bash starts until the field opens, and how long it stays open.
@export var open_after: float = 0.2
@export var open_time: float = 0.3
## Share of the holder's top speed while it's drawn.
@export_range(0.0, 1.0) var move_share: float = 0.85
## How far a heavy blow it stops shoves the holder back (m), within how many seconds.
@export var shove: float = 2.0
@export var shove_time: float = 0.2

@export_group("Sounds")
## A blow or a shot stopped, a heavy blow stopped, and the field's hum while it stands (a loop).
@export var block_sound: Sound
@export var heavy_sound: Sound
@export var hum_sound: Sound
