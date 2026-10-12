extends RefCounted
## The test map, landed at the small hand-built test location instead of starting in space and
## flying to a generated outside world: its ore nodes, rocks and nests sit at fixed spots near the
## ship, and it's quick to set up. Every location the ship flies to is a fresh test location.

const MAP: PackedScene = preload("res://scenes/maps/test_map.tscn")
const LOCATION: PackedScene = preload("res://scenes/locations/test_location.tscn")


static func instantiate() -> Node3D:
	var map := MAP.instantiate() as Node3D
	var mission := map.get_node("Mission") as Mission
	var ship := map.get_node("Ship") as Ship
	var location := LOCATION.instantiate() as Node3D
	location.name = Mission.LOCATION_NAME
	map.add_child(location)
	map.move_child(location, ship.get_index())
	# The ship starts landed there, and every location it flies to is a fresh one of it.
	mission.location = location
	mission.location_scene = LOCATION
	return map


## Picks the first mission on offer in `map` (in the tree), as if picked at the holo table, and
## lets the ship land there right away.
static func pick_mission(map: Node3D) -> void:
	var mission: Mission = map.get_node("Mission") as Mission
	mission.select(mission.offers[0])
	mission.skip_flight()
