class_name AlienNestSettings
extends Resource
## Alien nest tuning values. All values TBD (playtest). Values with a start and an end follow the
## mission's escalation: the start value when the mission starts, the end value from when the storm
## hits (see `Mission.progress`).

## Aliens that hatch when the nest appears and wait around it.
@export var guards: int = 2
## Seconds between hunters when the mission starts ...
@export var hunter_interval_start: float = 45.0
## ... and when the storm hits.
@export var hunter_interval_end: float = 15.0
## Hunters from one nest out at once when the mission starts ...
@export var max_hunters_start: int = 1
## ... and when the storm hits.
@export var max_hunters_end: int = 4
## Aliens hatch this far from the nest's center (horizontally, in m). Far enough out that waiting
## guards don't block the paths that hug the nest.
@export var hatch_radius: float = 3.5
