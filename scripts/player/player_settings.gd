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
