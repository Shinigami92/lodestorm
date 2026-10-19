class_name AlienCloak
extends Resource
## How a stalker hides (`AlienStrain.cloak`, see `AlienCloaking`): unseen and not lockable while no
## player is within `reveal_range`, a shimmer closer than that, and fully seen for `shown_time`
## after it starts an attack or takes a hit. An attack it starts from hiding hits harder
## (`ambush_damage`). All values TBD (playtest).

## Players closer than this (horizontally, m) see its shimmer and can lock on.
@export var reveal_range: float = 8.0
## Seconds it stays fully seen after it starts an attack or takes a hit.
@export var shown_time: float = 3.0
## Seconds it takes to fade in or out.
@export var fade_time: float = 0.4
## The damage of its first strike from hiding at least (before its tier's factor).
@export var ambush_damage: float = 30.0
## How far the shimmer bends what's behind it (a share of the screen).
@export var bend: float = 0.035
