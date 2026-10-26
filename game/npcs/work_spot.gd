class_name WorkSpot
extends Marker3D
## A place where a crew member works now and then besides their spot (see `Npc.work_spots`): they
## stand where it is (their feet), facing the way it faces, and play only its `activities` there
## (e.g. "Tap" at a console, "LookAround" at a window). See docs/planned/crew.md, Crew life aboard.

## The activities they play here (clips their model has, see `NpcProfile.activities`).
@export var activities: Array[StringName] = []
