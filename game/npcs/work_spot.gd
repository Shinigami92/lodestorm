class_name WorkSpot
extends Marker3D
## A place where an NPC works or stands now and then besides their spot (see `Npc.work_spots`):
## they stand where it is (their feet), facing the way it faces, and play only its `activities`
## there (e.g. "Tap" at a console, "LookAround" at a window). One outside their own room they only
## go to once their greeting is heard (see `NpcRoutine.move_on`). See docs/design/crew.md.

## The activities they play here (clips their model has, see `NpcProfile.activities`).
@export var activities: Array[StringName] = []
## How likely it's picked when they move on, against their own spot's 1 (e.g. 0.5: now and then).
## TBD (playtest).
@export_range(0.0, 4.0) var weight: float = 1.0
## Whether they're used here as at their own spot (e.g. across the same counter); else at their
## feet (see `NpcRoutine`).
@export var use_like_home: bool = false
