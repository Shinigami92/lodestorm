class_name RoomLooks
extends Resource
## Every room's RoomLook by the room's name (as in game/ship/hull_layout.py: "Armory", "Cabin3"):
## cabins and crew cabins share theirs ("Cabin", "Crew"), so a name's trailing number is dropped
## when it isn't listed itself.

@export var looks: Dictionary[StringName, RoomLook] = {}


func get_look(room: StringName) -> RoomLook:
	if looks.has(room):
		return looks[room]
	var base := String(room).rstrip("0123456789")
	return looks.get(StringName(base)) as RoomLook
