class_name SpaceStation
extends Node3D
## A station the ship docks at (a `CelestialBody` of kind station with this scene as its `map`;
## see docs/design/station.md): a handcrafted interior on one deck, standing where the ship
## stands like a location (its axes are the ship's), with the ship's tail reaching through the
## pressure frame into its hangar, the ramp leading down onto the hangar's deck. Built from data by
## its builder (e.g. `ostra/ostra_build.py`): `Walls` (its `Cut` child: the roofs and the walls
## facing the camera), `Rooms` (floors, lights, room names, floor guides), `Clamps` and `Interior`.
## The camera rules are the ship's: while the `viewer` is inside or aboard the docked ship, `Cut`
## only casts shadows (the walls leave low stubs), so the camera sees in.
## While the ship's `flight` docks or undocks, the station glides in or drifts off
## (`ShipFlight.station_offset`) and its clamps close around the hull or let go
## (`ShipFlight.clamp_amount`). Below it, the planet it orbits fills the view through its windows.

## How far the clamps pull back from the hull when open, in m.
const CLAMP_TRAVEL: float = 3.0
## The planet below (ship-local): its center and radius in m, 4 km away at 60° below the
## gallery, so its horizon lies about 27° below the level: seen through the back windows, it runs
## across the panes (within the camera's far plane).
const PLANET_CENTER := Vector3(150.0, -3464.0, -2028.0)
const PLANET_RADIUS: float = 2180.0

## The station it is (its planet's color shows below).
var body: CelestialBody
## The ship's flight: it moves the station while docking or undocking.
var flight: ShipFlight
## Whose view the cutaway follows (the camera's player); without one, the first player inside.
var viewer: Node3D
## The ship that docks here, found when not set: aboard it, the station is cut away too.
var ship: Ship:
	get:
		if not is_instance_valid(_ship) and is_inside_tree():
			_ship = Ship.nearest(get_tree(), global_position)
		return _ship
	set(value):
		_ship = value

var _inside: Array[Player] = []
var _cut_away: bool = false
var _docked_transform: Transform3D
## Each clamp and where it holds the hull.
var _clamps: Dictionary[Node3D, Vector3] = {}
var _ship: Ship

## Its rooms' areas (from its builder), for what people say where they stand.
@onready var room_plan: RoomPlan = $RoomPlan
@onready var _cut: Node3D = $Walls/Cut
@onready var _interior: Area3D = $Interior


func _ready() -> void:
	_docked_transform = transform
	for arm: Node3D in $Clamps.get_children():
		_clamps[arm] = arm.position
	_interior.body_entered.connect(_on_body_entered)
	_interior.body_exited.connect(_on_body_exited)
	add_child(_make_planet())
	CutAway.show(_cut, true)
	_follow_flight()


func _process(_delta: float) -> void:
	_follow_flight()
	var cut: bool = _viewer_within()
	if cut != _cut_away:
		_cut_away = cut
		CutAway.show(_cut, not cut)


## Whether `player` is inside the station.
func is_inside(player: Node3D) -> bool:
	return player in _inside


## Whether the station is cut away for the camera right now.
func is_cut_away() -> bool:
	return _cut_away


## Where it stands and how far its clamps are closed, from the flight (docked: where it was placed).
func _follow_flight() -> void:
	var offset: Vector3 = flight.station_offset() if flight else Vector3.ZERO
	var closed: float = flight.clamp_amount() if flight else 1.0
	var placed: Transform3D = _docked_transform.translated(_docked_transform.basis * offset)
	if not placed.is_equal_approx(transform):
		transform = placed
	for arm: Node3D in _clamps:
		var hold: Vector3 = _clamps[arm]
		arm.position = hold + Vector3(0.0, 0.0, signf(hold.z) * CLAMP_TRAVEL * (1.0 - closed))


## Whether the viewer (or else the first player inside) is inside the station or aboard the ship
## (unless the ship shows its outside, e.g. the title view).
func _viewer_within() -> bool:
	var who: Node3D = viewer
	if not who and not _inside.is_empty():
		who = _inside[0]
	if not who:
		return false
	var docked_ship: Ship = ship
	if docked_ship and docked_ship.show_outside:
		return false
	var player := who as Player
	return who in _inside or (docked_ship != null and player and docked_ship.is_aboard(player))


## The planet below, in its color, lit by the sun like the rest; not in the navigator's hologram.
func _make_planet() -> MeshInstance3D:
	var planet := MeshInstance3D.new()
	planet.name = "Planet"
	var mesh := SphereMesh.new()
	mesh.radius = PLANET_RADIUS
	mesh.height = PLANET_RADIUS * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	planet.mesh = mesh
	var material := StandardMaterial3D.new()
	var below: CelestialBody = body.orbits if body and body.orbits else body
	material.albedo_color = below.color if below else Color(0.75, 0.5, 0.35)
	material.roughness = 1.0
	material.disable_fog = true
	material.disable_receive_shadows = true
	planet.material_override = material
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.position = PLANET_CENTER
	planet.add_to_group(HoloTable.HIDDEN_GROUP)
	RenderLayers.put(planet, RenderLayers.EFFECTS)
	return planet


func _on_body_entered(entered: Node3D) -> void:
	var player := entered as Player
	if player and player not in _inside:
		_inside.append(player)


func _on_body_exited(exited: Node3D) -> void:
	var player := exited as Player
	if player:
		_inside.erase(player)
