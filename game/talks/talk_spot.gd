class_name TalkSpot
extends Marker3D
## Where two NPCs stand for an `OverheardTalk` (named by the node's name, unique aboard and at the
## stations): two places `GAP` m apart along its x axis, each facing the other and turned
## `OPEN_ANGLE` towards its front (+z), so both faces read from where the camera looks. The places
## are markers of their own (`Place1`, `Place2`), so they move with it (a station gliding in).

const GROUP: StringName = &"talk_spots"
## How far apart the two stand, in m.
const GAP: float = 1.4
## How far each turns from facing the other towards the front, in radians.
const OPEN_ANGLE: float = deg_to_rad(25.0)

var _places: Array[Marker3D] = []


func _ready() -> void:
	add_to_group(GROUP)
	for side: float in [-1.0, 1.0]:
		var place := Marker3D.new()
		place.name = "Place%d" % (_places.size() + 1)
		place.position = Vector3.RIGHT * side * GAP * 0.5
		# NPCs face +z: the first place faces +x, the second -x, both turned towards +z.
		place.rotation.y = -side * (PI * 0.5 - OPEN_ANGLE)
		add_child(place)
		_places.append(place)


## The place of the `index`th speaker (0 or 1).
func get_place(index: int) -> Marker3D:
	return _places[index]


## The spot named `id` in `tree`, or null.
static func find(tree: SceneTree, id: StringName) -> TalkSpot:
	for spot: TalkSpot in tree.get_nodes_in_group(GROUP):
		if spot.name == id:
			return spot
	return null
