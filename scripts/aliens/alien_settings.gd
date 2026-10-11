class_name AlienSettings
extends Resource
## Alien tuning values. All values TBD (playtest).

## Health of an unhurt alien.
@export var max_health: float = 30.0
## Top speed in m/s; below the player's, so running away works.
@export var move_speed: float = 4.5
## How fast the alien reaches top speed and stops again, in m/s².
@export var acceleration: float = 30.0
## How fast the body turns towards its target (higher = snappier).
@export var turn_speed: float = 10.0
## Players closer than this (horizontally, in m) get noticed and chased.
@export var detection_range: float = 18.0
## A chased player farther away than this (horizontally, in m) gets away.
@export var chase_range: float = 20.0
## The alien attacks when its target is this close (horizontally, center to center, in m).
@export var attack_range: float = 1.4
## Damage per attack.
@export var attack_damage: float = 10.0
## Attacks per second while the target is in reach.
@export var attack_rate: float = 1.0
