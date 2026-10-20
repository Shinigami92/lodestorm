class_name RangedWeaponSettings
extends WeaponSettings
## Tuning values of projectile weapons. All values TBD (playtest).

## How a reload fills the weapon: the whole magazine at once (the rounds left in it are lost), or
## one round after another (the loaded ones stay).
enum ReloadMode { MAGAZINE, SINGLE }

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

@export_group("Ammo")
## Rounds (shots) a full magazine holds at MK1.
@export var magazine: int = 24
## Ore one round costs, in units of the commonest ore (see `OreType.ammo_yield`).
@export var ore_per_round: float = 0.25
@export var reload_mode: ReloadMode = ReloadMode.MAGAZINE
## Seconds a reload takes: the whole magazine, or one round with `ReloadMode.SINGLE`.
@export var reload_time: float = 1.6
## The timing window of a reload, as shares of the reload time: pressing `reload` within it
## finishes the reload (the round) right away, pressing it outside adds `fumble_time`.
@export var sweet_spot_start: float = 0.55
@export var sweet_spot_width: float = 0.15
@export var fumble_time: float = 0.5
## `ReloadMode.SINGLE`: each round in a row loaded within the window makes the next ones quicker by
## this share of the reload time, up to `max_chain_speedup`.
@export var chain_speedup: float = 0.1
@export var max_chain_speedup: float = 0.3

@export_group("Sounds")
## A reload starting.
@export var reload_sound: Sound
## The rounds going in: the magazine at the end of a reload, or each single round.
@export var load_sound: Sound
