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
