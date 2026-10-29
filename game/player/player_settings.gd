class_name PlayerSettings
extends Resource
## Player tuning values. All values TBD (playtest).

## Top speed in m/s.
@export var move_speed: float = 6.0
## How fast the player reaches top speed and stops again, in m/s².
@export var acceleration: float = 40.0
## How fast the body turns towards the aim direction (higher = snappier).
@export var turn_speed: float = 20.0
## How close (horizontally, in m) the player must be to an ore node's center to place a miner.
@export var miner_place_range: float = 2.5
## Health of an unhurt player.
@export var max_health: float = 100.0
## Target lock: the cursor locks on an alien within this distance on screen (a share of the
## screen height) and lets go beyond `target_release_radius`.
@export var target_lock_radius: float = 0.04
@export var target_release_radius: float = 0.07
## Target lock with the right stick: the nearest alien within this angle of the stick direction
## (degrees) and this distance (m).
@export var stick_lock_angle: float = 12.0
@export var stick_lock_range: float = 25.0
## Weapons a player takes into a mission (see `Loadout`).
@export var loadout_slots: int = 2
## Spare magazines per ranged weapon a run starts with (besides the loaded one).
@export var spare_magazines: int = 2
## Share of the top speed while reloading.
@export var reload_move_speed: float = 0.75
## Handing a teammate ammo: holding `interact` this long (s) within this distance (m) of them.
@export var give_ammo_time: float = 0.8
@export var give_ammo_range: float = 2.0
## Dash (a skill): how far it goes (m), how long it takes (s) and how long until the next (s).
@export var dash_distance: float = 4.0
@export var dash_time: float = 0.18
@export var dash_cooldown: float = 2.0
## Regeneration (a skill) starts this long (s) after the last damage.
@export var regeneration_delay: float = 5.0
## The rescue drone (a skill) gets a downed player up with this share of their health: after at
## least `rescue_time` (s), once no alien is within `rescue_gap` (m), at most `rescue_wait` (s).
@export var rescue_time: float = 3.0
@export var rescue_wait: float = 8.0
@export var rescue_gap: float = 10.0
@export var rescue_health: float = 0.5
## Its flash as it flies out staggers the aliens within this range (m) for this long (s), pushing
## them away (m/s).
@export var rescue_flash_range: float = 8.0
@export var rescue_flash_stagger: float = 2.0
@export var rescue_flash_push: float = 6.0
