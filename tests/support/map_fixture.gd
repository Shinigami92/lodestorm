extends RefCounted
## The test map, landed at the small hand-built test location instead of starting in space and
## flying to a generated outside world: its ore nodes, rocks and nests sit at fixed spots near the
## ship, and it's quick to set up. Every location the ship flies to is a fresh test location.
## The whole crew is aboard unless a test asks for a new game's start (`crew_joined` false).

const MAP: PackedScene = preload("res://game/maps/main.tscn")
const LOCATION: PackedScene = preload("res://game/locations/test_location.tscn")


static func instantiate(crew_joined: bool = true) -> Node3D:
	var map := MAP.instantiate() as Node3D
	var voyage := map.get_node("Voyage") as Voyage
	var ship := map.get_node("Ship") as Ship
	ship.crew_joins_later = not crew_joined
	if crew_joined:
		NpcProfile.join_whole_crew(ship.story)
	var location := LOCATION.instantiate() as Node3D
	location.name = Voyage.LOCATION_NAME
	map.add_child(location)
	map.move_child(location, ship.get_index())
	# The ship starts landed there, and every location it flies to is a fresh one of it.
	voyage.location = location
	voyage.location_scene = LOCATION
	return map


## Picks the first mission on offer in `map` (in the tree), as if picked at the holo table, and
## lets the ship land there right away.
static func pick_mission(map: Node3D) -> void:
	var voyage: Voyage = map.get_node("Voyage") as Voyage
	voyage.select(voyage.offers[0])
	voyage.skip_flight()
