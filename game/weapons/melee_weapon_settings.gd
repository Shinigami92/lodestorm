class_name MeleeWeaponSettings
extends WeaponSettings
## Tuning values of melee weapons. All values TBD (playtest).

## Damage per swing to every alien it hits.
@export var damage: float = 30.0
## How far a swing reaches, from the holder to an alien's center (horizontally, in m).
@export var reach: float = 2.5
## Width of the swing around the attack direction, in degrees.
@export var arc: float = 120.0

@export_group("Sounds")
## A swing that hits something.
@export var hit_sound: Sound
