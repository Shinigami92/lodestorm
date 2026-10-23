class_name FlightStation
extends Station
## The cockpit's flight console: it shows the destination picked at the navigator and sets course
## for it (`Voyage.confirm`): its part is the launch lever, and `interact` (or the card's "Set
## course") pulls it. The lever stays pulled while the ship flies.

## The lever's angle (degrees, around its Z): resting (tilted towards the window, -X), and pulled
## back towards the pilot during a flight.
const LEVER_REST: float = 20.0
const LEVER_PULLED: float = -35.0

## Where the ship goes: course is set for its destination; found in the scene tree when not set.
var voyage: Voyage

@onready var _handle: Node3D = $Lever/Handle


func _process(delta: float) -> void:
	super(delta)
	if not voyage:
		voyage = get_tree().get_first_node_in_group(Voyage.GROUP) as Voyage
	var flying: bool = voyage != null and voyage.flight.is_flying()
	var goal: float = deg_to_rad(LEVER_PULLED if flying else LEVER_REST)
	_handle.rotation.z = lerp_angle(_handle.rotation.z, goal, 1.0 - exp(-10.0 * delta))
	if user:
		refresh()


## Whether course can be set now (a destination picked, nothing locks it).
func can_launch() -> bool:
	return voyage != null and voyage.can_confirm()


## Sets course for the destination. Returns whether it did.
func launch() -> bool:
	return can_launch() and voyage.confirm()
