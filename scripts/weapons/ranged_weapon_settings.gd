class_name RangedWeaponSettings
extends WeaponSettings
## Tuning values of projectile weapons. All values TBD (playtest).

## Damage per projectile.
@export var damage: float = 10.0
## Projectile speed in m/s.
@export var projectile_speed: float = 30.0
## Distance in m after which a projectile disappears.
@export var projectile_range: float = 25.0
## Projectiles per shot (a shotgun fires several).
@export var pellets: int = 1
## Width of the fan the pellets fly in, around the attack direction, in degrees.
@export var spread: float = 0.0
