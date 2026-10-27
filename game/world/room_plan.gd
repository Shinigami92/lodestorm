class_name RoomPlan
extends Node3D
## The rooms of a map people walk in (the ship's hull, a station), written by its builder from
## the layout (game/ship/hull_build.py, game/space_station/ostra/ostra_build.py): each room's floor
## areas as boxes in this node's space, from the floor up to the ceiling, between the walls'
## centers (so they meet in the doorways). A room with several areas (an L-shaped hall) is listed
## once per area. `room_at` says which room a point is in, e.g. for what an NPC says there (see
## `NpcRoutine.is_away`).

## How far past a room's walls a point still counts as in it, when it was in it before (a
## doorway belongs to the room someone comes from), in m.
const KEEP_MARGIN: float = 0.6
## How far below a room's floor a point still counts (feet a hair below it, the lift's platform).
const BELOW_FLOOR: float = 0.5

## Each area's room (its node name in the map, e.g. "Armory"), and the area.
@export var rooms: Array[StringName] = []
@export var areas: Array[AABB] = []


## The room `point` (global) is in: `keep` (the room it was in before) while it's within
## `KEEP_MARGIN` m of it, else the first room with an area around it; `keep` when it's in none
## (outside, or the plan has none), so a doorway or a gap between areas never loses it.
func room_at(point: Vector3, keep: StringName = &"") -> StringName:
	var local: Vector3 = global_transform.affine_inverse() * point
	if not keep.is_empty() and _contains(keep, local, KEEP_MARGIN):
		return keep
	for i: int in areas.size():
		if _inside(areas[i], local, 0.0):
			return rooms[i]
	return keep


## Whether `local` (in this node's space) lies in an area of `room`, grown by `margin` m around.
func _contains(room: StringName, local: Vector3, margin: float) -> bool:
	for i: int in areas.size():
		if rooms[i] == room and _inside(areas[i], local, margin):
			return true
	return false


static func _inside(area: AABB, local: Vector3, margin: float) -> bool:
	var grown: AABB = area.grow(margin)
	return (
		local.x >= grown.position.x
		and local.x <= grown.end.x
		and local.z >= grown.position.z
		and local.z <= grown.end.z
		and local.y >= area.position.y - BELOW_FLOOR
		and local.y <= area.end.y
	)
