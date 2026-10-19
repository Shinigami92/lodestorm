class_name AlienNestSettings
extends Resource
## Alien nest tuning values. All values TBD (playtest). Values with a start and an end follow the
## mission's escalation: the start value when the mission starts, the end value from when the storm
## hits (see `Mission.progress`). Hunters and raiders out at once count by their cap share
## (`AlienStrain.cap_share`: a swarmer 1, a mite a quarter).

## Packs that hatch when the nest appears and wait around it (see `AlienPack`).
@export var guard_packs: int = 1
## Seconds between packs of hunters when the mission starts ...
@export var hunter_interval_start: float = 60.0
## ... and when the storm hits.
@export var hunter_interval_end: float = 20.0
## Hunters from one nest out at once when the mission starts ... (a pack hatches while fewer are
## out, so one pack may go over it)
@export var max_hunters_start: float = 1.0
## ... and when the storm hits.
@export var max_hunters_end: float = 5.0
## Seconds between raiders when the mission starts ...
@export var raider_interval_start: float = 60.0
## ... and when the storm hits.
@export var raider_interval_end: float = 25.0
## Raiders from one nest out at once when the mission starts ...
@export var max_raiders_start: float = 1.0
## ... and when the storm hits.
@export var max_raiders_end: float = 2.0
## Aliens hatch this far from the nest's center (horizontally, in m). Far enough out that waiting
## guards don't block the paths that hug the nest.
@export var hatch_radius: float = 3.5
## How many aliens may live at once, from all nests together (see `AlienStrain.cap_share`); nests
## wait while it's reached. Lower in VR.
@export var max_aliens: float = 60.0
@export var max_aliens_vr: float = 40.0
## Guards take at most this share of the cap, so hunters and raiders still hatch on big maps with
## many nests (nests whose guards don't fit wait without them).
@export_range(0.0, 1.0) var guard_share: float = 0.5


## How many aliens may live at once (see `max_aliens`).
func alien_cap() -> float:
	var xr: XRInterface = XRServer.primary_interface
	return max_aliens_vr if xr and xr.is_initialized() else max_aliens
