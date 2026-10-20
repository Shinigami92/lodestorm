class_name WeaponSettings
extends Resource
## Tuning values every weapon has. All values TBD (playtest).

## Attacks (shots, swings) per second while the attack button is held.
@export var attack_rate: float = 6.0
## Stagger each hit (projectile, swing) adds to an alien (see `AlienStrain.stagger_threshold`).
@export var stagger: float = 7.0
## How hard each hit pushes an alien back, in m/s (it fades within a fraction of a second).
@export var push: float = 0.5

@export_group("Sounds")
## Each attack (a shot, a swing).
@export var attack_sound: Sound
