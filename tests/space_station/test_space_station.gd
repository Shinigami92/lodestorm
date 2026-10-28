extends GutTest

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const DIRECTORY: String = "user://test_station_save/"

var _map: Node3D
var _player: Player
var _mission: Mission
var _voyage: Voyage
var _ship: Ship
var _ostra: CelestialBody


func before_each() -> void:
	SaveGame.directory = DIRECTORY
	_clean()
	await _start()


func after_each() -> void:
	_clean()
	SaveGame.directory = ""


func test_ostra_can_be_docked_at_from_the_start() -> void:
	assert_true(_ostra.is_dockable())
	assert_true(_ostra.is_reachable(1), "no tier needed")
	assert_eq(_ostra.orbits.id, &"torvane", "it orbits the colony's planet")
	var offer: MissionBrief = _voyage.offer_for_station(_ostra)
	assert_not_null(offer)
	assert_eq(offer.location_name(), "Waypost Ostra")
	assert_null(offer.region, "no mission there")
	assert_eq(_voyage.ship_body().kind, CelestialBody.Kind.PLANET, "a new game starts at a planet")


## The flight crosses space with the station growing behind the hull, then the station glides in
## and the clamps take hold: no clouds.
func test_flight_ends_docking() -> void:
	var flight: ShipFlight = _ship.flight
	assert_true(_voyage.select(_voyage.offer_for_station(_ostra)))
	assert_eq(flight.phase, ShipFlight.Phase.TAKEOFF, "from the location, the take-off first")
	assert_eq(_voyage.at_body, _ostra)
	await _advance_to(ShipFlight.Phase.DEPARTURE)
	assert_eq(flight.phase_duration(), flight.settings.travel_time, "the long way through space")
	flight.phase_time = flight.phase_duration() * 0.5
	assert_gt(flight.destination_amount(), 0.0, "the station grows behind the hull")
	await _advance_to(ShipFlight.Phase.DOCKING)
	var station := _voyage.location as SpaceStation
	assert_not_null(station, "comes into view as the docking starts")
	assert_eq(flight.cloud_amount(), 0.0, "no clouds")
	assert_eq(flight.space_amount(), 1.0)
	await wait_process_frames(1)
	var far: float = station.position.distance_to(_ship.position)
	assert_gt(far, 100.0, "still gliding in")
	assert_eq(flight.clamp_amount(), 0.0)
	flight.phase_time = flight.phase_duration() - 0.001
	await wait_process_frames(1)
	assert_almost_eq(station.position.distance_to(_ship.position), 0.0, 0.01, "in place")
	assert_gt(flight.clamp_amount(), 0.99, "the clamps take hold")
	var held: Node3D = station.get_node("Clamps/Clamp1")
	assert_almost_eq(absf(held.position.z), 17.8, 0.05, "against the hull's lower side")
	flight.skip()
	assert_true(flight.is_docked())
	assert_false(flight.is_flying())
	assert_eq(_ship.countdown_text, "Docked")


## Docked: the ramp leads into the hangar and goes down and up freely, weapons stay holstered, and
## there's no timer or run.
func test_ramp_into_the_hangar() -> void:
	await _dock()
	assert_true(_ship.ramp_button.enabled)
	_ship.ramp_button.use(_player)
	await _ramp_moves()
	assert_true(_ship.is_ramp_down())
	assert_eq(_mission.state, Mission.State.CLOSED, "no run")
	_ship.ramp_button.use(_player)
	await _ramp_moves()
	assert_true(_ship.is_ramp_up(), "up again")
	_ship.ramp_button.use(_player)
	await _ramp_moves()
	var station := _voyage.location as SpaceStation
	var foot: Vector3 = _ship.to_global(Vector3(19.8, 0.0, 0.0))
	var hit: Dictionary = _ray_down(foot)
	assert_false(hit.is_empty(), "the ramp reaches the hangar's deck")
	await _move(foot + Vector3(4.0, 0.1, 0.0))
	assert_true(station.is_inside(_player))
	assert_false(_ship.is_aboard(_player))
	assert_false(_player.arms.allowed, "holstered at the station")
	assert_eq(_mission.state, Mission.State.CLOSED, "stepping out starts nothing")
	assert_true(station.is_cut_away(), "the camera sees in")
	var roof: GeometryInstance3D = station.get_node("Walls/Cut/RoofHangar")
	assert_eq(roof.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)


## Leaving takes everyone aboard; the ramp goes up by itself and the ship undocks, then flies on.
func test_leaving_undocks() -> void:
	await _dock()
	_ship.ramp_button.use(_player)
	await _ramp_moves()
	await _move(_ship.to_global(Vector3(30.0, 0.1, 0.0)))
	var offer: MissionBrief = _voyage.offers[0]
	assert_true(_voyage.choose(offer))
	assert_false(_voyage.can_confirm(), "someone is still in the station")
	await _move(_ship.to_global(Vector3(10.0, 2.6, 0.0)))
	assert_true(_voyage.can_confirm())
	assert_true(_voyage.confirm())
	assert_false(_ship.ramp_open, "the ramp goes up")
	assert_eq(_ship.flight.phase, ShipFlight.Phase.UNDOCKING)
	assert_gt(_ship.flight.phase_duration(), 0.0)
	await _advance_to(ShipFlight.Phase.DEPARTURE)
	assert_null(_voyage.location, "the station is left behind")
	_voyage.skip_flight()
	assert_eq(_ship.flight.phase, ShipFlight.Phase.LANDED)
	assert_eq(_voyage.brief, offer)
	assert_ne(_voyage.at_body, _ostra)


func test_the_map_from_data() -> void:
	await _dock()
	var station := _voyage.location as SpaceStation
	var rooms: Array[String] = ["Hangar", "Concourse", "Depot", "Council", "Bar", "Gallery"]
	var far: float = 0.0
	for room: String in rooms:
		var node: Node3D = station.get_node("Rooms/" + room)
		var floor_mesh: MeshInstance3D = node.get_node("Floor")
		assert_false(_ray_down(floor_mesh.global_position).is_empty(), room + " has a deck")
		assert_not_null(node.get_node_or_null("Sign"), room + " has its name on the floor")
		far = maxf(far, _ship.to_local(floor_mesh.global_position).x)
	assert_gt(far, 120.0, "the far end is a walk away from the ramp")
	var guides: Array[Node] = station.find_children("*", "FloorGuide", true, false)
	assert_gt(guides.size(), 5, "floor guides lead the way")
	assert_true(station.get_node("Walls/Cut").is_in_group(HoloTable.HIDDEN_GROUP))


func test_navigator_picks_the_station_like_a_region() -> void:
	var navigator := _ship.get_node("Rooms/Upper/Bridge/Navigator") as NavigatorStation
	await _move(navigator.global_position + navigator.global_basis.z * 2.8)
	assert_eq(_player.interact(), navigator.use_point)
	await wait_process_frames(1)
	navigator.select(navigator.get_part(_ostra))
	assert_true(navigator.activate(), "zooms into it")
	assert_eq(navigator.level, NavigatorStation.Level.BODY)
	assert_eq(_voyage.previewed, _voyage.offer_for_station(_ostra), "its map on the table")
	assert_eq(navigator.get_parts().size(), 1)
	assert_null(_voyage.destination, "only looking")
	await wait_seconds(1.0)
	assert_eq(navigator.zoom, 1.0, "no further")
	var table: HoloTable = _ship.get_node("Rooms/Upper/Bridge/HoloTable") as HoloTable
	assert_true((table.get_node("Hologram") as Node3D).visible, "the map shows")
	assert_true(navigator.activate(), "interact chooses it")
	assert_eq(_voyage.destination, _voyage.offer_for_station(_ostra))
	assert_eq(navigator.destination_body(), _ostra)
	navigator.set_zoom_target(2.0)
	assert_eq(navigator.zoom_target, 1.0, "a station has no landing site")


func test_docked_ship_is_saved() -> void:
	await _dock()
	var save := _map.get_node("SaveGame") as SaveGame
	var at: String = SaveGame.ship_data(_ship)["at"]
	assert_eq(at, "ostra")
	save.save_progress()
	_map.free()
	await _start()
	await wait_process_frames(2)
	assert_true(_ship.flight.is_docked(), "docked again")
	assert_true(_voyage.location is SpaceStation, "the station around the ship")
	assert_eq(_voyage.brief, _voyage.offer_for_station(_ostra))
	assert_true(_ship.ramp_button.enabled)


func _start() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_mission = _map.get_node("Mission") as Mission
	_voyage = _map.get_node("Voyage") as Voyage
	_ship = _map.get_node("Ship") as Ship
	_ship.ramp_duration = 0.25
	_ostra = _voyage.settings.system.body_by_id(&"ostra")
	await wait_physics_frames(2)


func _dock() -> void:
	_voyage.select(_voyage.offer_for_station(_ostra))
	_voyage.skip_flight()
	await wait_physics_frames(2)


## Runs the flight's phases until it's in `phase`.
func _advance_to(phase: ShipFlight.Phase) -> void:
	var flight: ShipFlight = _ship.flight
	for i: int in 10:
		if flight.phase == phase:
			return
		flight.phase_time = flight.phase_duration()
		await wait_physics_frames(1)
	assert_eq(flight.phase, phase)


func _ramp_moves() -> void:
	await wait_physics_frames(ceili(_ship.ramp_duration * Engine.physics_ticks_per_second) + 2)


func _ray_down(from: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		from + Vector3.UP * 1.0, from + Vector3.DOWN * 2.0, PhysicsLayers.WORLD
	)
	query.exclude = [_player.get_rid()]
	return _ship.get_world_3d().direct_space_state.intersect_ray(query)


func _move(target: Vector3) -> void:
	_player.global_position = target
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)


func _clean() -> void:
	SaveGame.erase()
	if FileAccess.file_exists(GameSettings.path()):
		DirAccess.remove_absolute(GameSettings.path())
