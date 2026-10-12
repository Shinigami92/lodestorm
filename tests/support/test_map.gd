extends RefCounted
## The test map with the small hand-built test location instead of a generated outside world: its
## ore nodes, rocks and nests sit at fixed spots near the ship, and it's quick to set up.

const MAP: PackedScene = preload("res://scenes/maps/test_map.tscn")
const LOCATION: PackedScene = preload("res://scenes/locations/test_location.tscn")


static func instantiate() -> Node3D:
	var map := MAP.instantiate() as Node3D
	var generated: Node = map.get_node("Location")
	var location := LOCATION.instantiate() as Node3D
	location.name = generated.name
	var index: int = generated.get_index()
	map.remove_child(generated)
	generated.free()
	map.add_child(location)
	map.move_child(location, index)
	# Exported node references are resolved when the map is instantiated.
	(map.get_node("Mission") as Mission).location = location
	return map


## Picks the first mission on offer in `map` (in the tree), as if picked at the holo table.
static func pick_mission(map: Node3D) -> void:
	var mission: Mission = map.get_node("Mission") as Mission
	mission.select(mission.offers[0])
