extends GutTest

const TEST_MAP := preload("res://tests/support/map_fixture.gd")

var _map: Node3D
var _player: Player
var _mission: Mission
var _voyage: Voyage
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_mission = _map.get_node("Mission") as Mission
	_voyage = _map.get_node("Voyage") as Voyage
	_ship = _map.get_node("Ship") as Ship
	_ship.ramp_duration = 0.25
	watch_signals(_mission)
	watch_signals(_voyage)
	await wait_physics_frames(2)


func test_offers_a_mission_per_open_region() -> void:
	var system: StarSystem = _voyage.settings.system
	var regions: Array[Region] = system.open_regions(_ship.heat_shield.mk)
	assert_gt(regions.size(), 1)
	assert_eq(_voyage.offers.size(), regions.size())
	for i: int in regions.size():
		var offer: MissionBrief = _voyage.offers[i]
		var region: Region = regions[i]
		assert_eq(offer.region, region)
		assert_eq(offer.biome, region.biome)
		assert_eq(offer.difficulty, region.danger, "the region sets the danger")
		assert_eq(offer.length, region.length, "and the timer")
		assert_gt(offer.world_seed, 0)
		assert_string_starts_with(offer.location_name(), region.display_name)
		assert_eq(_voyage.offer_for(region), offer)
	assert_null(_voyage.brief, "none is picked at the start")


func test_star_system_has_planets_moons_a_station_and_locked_planets() -> void:
	var system: StarSystem = _voyage.settings.system
	var kinds: Array = []
	var locked: Array[CelestialBody] = []
	for body: CelestialBody in system.bodies:
		kinds.append(body.kind)
		for region: Region in body.regions:
			assert_eq(system.body_of(region), body)
			assert_not_null(region.biome)
		if body.kind in [CelestialBody.Kind.STATION, CelestialBody.Kind.GAS_GIANT]:
			assert_false(body.is_reachable(99), "no docking yet, nowhere to land")
		elif not body.is_reachable(_ship.heat_shield.mk):
			locked.append(body)
	for kind: CelestialBody.Kind in CelestialBody.Kind.values():
		assert_has(kinds, kind)
	assert_gt(locked.size(), 0, "planets still locked")
	for body: CelestialBody in locked:
		for region: Region in body.regions:
			assert_false(region in system.open_regions(_ship.heat_shield.mk), "offers no missions")
			assert_null(_voyage.offer_for(region))


## Another heat shield plate adds the next planet's offers and keeps the others (and the
## destination).
func test_next_shield_plate_adds_offers() -> void:
	var system: StarSystem = _voyage.settings.system
	var opened: Array[Region] = []
	for body: CelestialBody in system.bodies:
		if body.tier == 2:
			opened.append_array(body.regions)
	assert_gt(opened.size(), 0)
	var before: Array[MissionBrief] = _voyage.offers.duplicate()
	assert_true(_voyage.choose(before[0]))
	assert_true(_ship.heat_shield.install_next())
	assert_eq(_voyage.offers.size(), before.size() + opened.size())
	assert_eq(_voyage.offers.slice(0, before.size()), before, "keeps the others")
	for region: Region in opened:
		assert_eq(_voyage.offer_for(region).region, region)
	assert_eq(_voyage.destination, before[0])


func test_ramp_needs_a_picked_mission() -> void:
	assert_false(_ship.ramp_button.enabled)
	_ship.ramp_button.use(_player)
	await wait_physics_frames(2)
	assert_eq(_mission.state, Mission.State.CLOSED)
	assert_eq(_ship.countdown_text, "No mission")
	assert_true(_voyage.select(_voyage.offers[0]))
	_voyage.skip_flight()
	await wait_physics_frames(2)
	# The countdown updates in _process.
	await wait_process_frames(2)
	assert_true(_ship.ramp_button.enabled)
	var seconds: int = ceili(_mission.duration())
	assert_eq(_ship.countdown_text, "%d:%02d" % [floori(seconds / 60.0), seconds % 60])
	_ship.ramp_button.use(_player)
	assert_eq(_mission.state, Mission.State.OPEN)


func test_picking_flies_to_the_mission() -> void:
	var offer: MissionBrief = _voyage.offers[2]
	var old_location: Node3D = _voyage.location
	assert_true(_voyage.select(offer))
	assert_eq(_voyage.brief, offer)
	assert_signal_emitted_with_parameters(_voyage, "selected", [offer])
	assert_eq(_mission.duration(), _mission.settings.duration * offer.length)
	assert_eq(_mission.time_left, _mission.duration())
	assert_true(_ship.flight.is_flying())
	_voyage.skip_flight()
	assert_true(old_location.is_queued_for_deletion(), "a fresh outside world")
	assert_eq(_voyage.location.name, &"Location")
	assert_ne(_voyage.location, old_location)


func test_only_offered_missions_can_be_picked() -> void:
	var other := MissionBrief.new()
	assert_false(_voyage.select(other))
	assert_null(_voyage.brief)


func test_mission_is_locked_once_the_ramp_is_down() -> void:
	TEST_MAP.pick_mission(_map)
	assert_true(_voyage.select(_voyage.offers[1]), "another one can be picked before leaving")
	_voyage.skip_flight()
	assert_eq(_voyage.brief, _voyage.offers[1])
	_ship.ramp_button.use(_player)
	assert_false(_voyage.can_select())
	assert_false(_voyage.select(_voyage.offers[2]))
	assert_eq(_voyage.brief, _voyage.offers[1])
	_ship.ramp_button.use(_player)
	assert_eq(_mission.state, Mission.State.CLOSED, "the ramp went up again before leaving")
	assert_true(_voyage.can_select())


func test_finished_mission_brings_new_offers() -> void:
	TEST_MAP.pick_mission(_map)
	var old_offers: Array[MissionBrief] = _voyage.offers.duplicate()
	_ship.ramp_button.use(_player)
	await wait_physics_frames(ceili(_ship.ramp_duration * Engine.physics_ticks_per_second) + 2)
	await _move(_ship.to_global(Vector3(22.0, 0.0, 0.0)))
	assert_eq(_mission.state, Mission.State.RUNNING)
	await _move(_ship.to_global(Vector3(10.0, 2.5, 0.0)))
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_null(_voyage.brief)
	assert_eq(_voyage.offers.size(), old_offers.size())
	for i: int in _voyage.offers.size():
		assert_does_not_have(old_offers, _voyage.offers[i])
		assert_eq(_voyage.offers[i].region, old_offers[i].region, "the same regions")
		assert_ne(_voyage.offers[i].world_seed, old_offers[i].world_seed, "a new section")
	assert_true(_voyage.can_select())


func test_picking_only_previews_until_course_is_set() -> void:
	var offer: MissionBrief = _voyage.offers[1]
	var old_location: Node3D = _voyage.location
	assert_true(_voyage.preview(offer))
	assert_eq(_voyage.previewed, offer)
	assert_null(_voyage.destination, "only shown")
	assert_null(_voyage.brief)
	assert_signal_not_emitted(_voyage, "selected")
	assert_false(_ship.flight.is_flying())
	assert_eq(_voyage.location, old_location)
	assert_false(_voyage.confirm(), "nothing chosen yet")
	assert_true(_voyage.preview(_voyage.offers[2]), "another one to compare")
	assert_true(_voyage.choose(_voyage.offers[2]))
	assert_true(_voyage.confirm())
	assert_eq(_voyage.brief, _voyage.offers[2])


func test_hologram_marks_the_ore_fields() -> void:
	var table: HoloTable = _ship.get_node("Rooms/Upper/Bridge/HoloTable") as HoloTable
	TEST_MAP.pick_mission(_map)
	var ores: Array[OreNode] = []
	for ore: OreNode in get_tree().get_nodes_in_group(OreNode.GROUP):
		if _voyage.location.is_ancestor_of(ore):
			ores.append(ore)
	var markers: Array[MeshInstance3D] = table.get_markers()
	assert_eq(markers.size(), ores.size())
	var colors: Array[Color] = []
	for marker: MeshInstance3D in markers:
		var material := marker.material_override as ShaderMaterial
		colors.append(material.get_shader_parameter(&"color"))
	for ore: OreNode in ores:
		assert_has(colors, ore.ore_type.color)
	var to_table: Transform3D = table.global_transform.affine_inverse()
	for marker: MeshInstance3D in markers:
		var at: Vector3 = to_table * marker.global_position
		assert_lt(Vector2(at.x, at.z).length(), table.radius * 1.5, "above the table")


func test_navigator_zooms_from_system_to_landing_site() -> void:
	var navigator: NavigatorStation = await _use_navigator()
	assert_eq(navigator.level, NavigatorStation.Level.SYSTEM)
	var system: StarSystem = _voyage.settings.system
	assert_eq(navigator.get_parts().size(), system.bodies.size() + 1, "one per body, and the star")
	var planet: CelestialBody = system.bodies[0]
	navigator.select(navigator.get_part(planet))
	assert_true(navigator.activate(), "zooms to the planet")
	assert_eq(navigator.level, NavigatorStation.Level.BODY)
	assert_eq(navigator.get_parts().size(), planet.regions.size(), "one per region")
	var region: Region = planet.regions[1]
	navigator.select(navigator.get_part(region))
	assert_true(navigator.activate(), "zooms to its landing site")
	assert_eq(navigator.level, NavigatorStation.Level.REGION)
	assert_eq(_voyage.previewed, _voyage.offer_for(region), "shown on the table")
	assert_null(_voyage.destination, "zooming in doesn't choose it")
	assert_true(navigator.activate(), "interact there chooses it")
	assert_eq(_voyage.destination, _voyage.offer_for(region))
	assert_null(_voyage.brief, "course is set at the cockpit")
	assert_false(_ship.flight.is_flying())
	var table: HoloTable = _ship.get_node("Rooms/Upper/Bridge/HoloTable") as HoloTable
	await wait_seconds(1.0)
	assert_eq(navigator.zoom, 2.0, "zoomed smoothly all the way in")
	assert_true((table.get_node("Hologram") as Node3D).visible, "the landing site")
	_send(&"pause")
	assert_eq(navigator.level, NavigatorStation.Level.BODY, "back steps out a level")
	await wait_seconds(1.0)
	assert_false((table.get_node("Hologram") as Node3D).visible, "the globe instead")
	assert_eq(navigator.selected.item, region, "where it came from")
	_send(&"pause")
	assert_eq(navigator.level, NavigatorStation.Level.SYSTEM)
	assert_eq(navigator.user, _player)
	_send(&"pause")
	assert_null(navigator.user, "closes at the star system")
	await wait_seconds(1.0)
	assert_false((table.get_node("Hologram") as Node3D).visible, "the table keeps the system")


func test_navigator_stays_where_it_was_left() -> void:
	var navigator: NavigatorStation = await _use_navigator()
	var moon: CelestialBody = _voyage.settings.system.bodies[1]
	navigator.select(navigator.get_part(moon))
	assert_true(navigator.activate())
	navigator.close()
	await wait_seconds(0.8)
	assert_eq(navigator.level, NavigatorStation.Level.BODY, "the table keeps showing the moon")
	assert_almost_eq(navigator.zoom, 1.0, 0.01, "and finishes zooming")
	navigator.open(_player)
	assert_eq(navigator.level, NavigatorStation.Level.BODY, "carries on there")
	assert_eq(navigator.body, moon)


func test_star_shows_its_name() -> void:
	var navigator: NavigatorStation = await _use_navigator()
	var system: StarSystem = _voyage.settings.system
	var star: StationPart = navigator.get_part(system)
	assert_not_null(star)
	navigator.select(star)
	assert_false(navigator.activate(), "nothing to zoom into")
	assert_eq(navigator.level, NavigatorStation.Level.SYSTEM)
	# Zooming towards it (the wheel) stops short, without errors (once broke the globe).
	for i: int in 5:
		navigator.set_zoom_target(navigator.zoom_target + NavigatorStation.WHEEL_STEP)
	await wait_seconds(0.5)
	assert_lt(navigator.zoom_target, 1.0)


func test_stations_and_locked_planets_cannot_be_visited() -> void:
	var navigator: NavigatorStation = await _use_navigator()
	for body: CelestialBody in _voyage.settings.system.bodies:
		if not navigator.is_reachable(body):
			navigator.select(navigator.get_part(body))
			assert_false(navigator.activate(), body.display_name)
			assert_eq(navigator.level, NavigatorStation.Level.SYSTEM)
			assert_lt(navigator.zoom_target, 1.0, "zooming stops short of it")
			navigator.show_system()


func test_mouse_wheel_zooms_gradually() -> void:
	var navigator: NavigatorStation = await _use_navigator()
	var planet: CelestialBody = _voyage.settings.system.bodies[0]
	navigator.select(navigator.get_part(planet))
	for i: int in 3:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		get_viewport().push_input(wheel, true)
	assert_almost_eq(navigator.zoom_target, 3 * NavigatorStation.WHEEL_STEP, 0.001)
	assert_eq(navigator.level, NavigatorStation.Level.SYSTEM, "not there yet")
	await wait_seconds(1.0)
	assert_almost_eq(navigator.zoom, navigator.zoom_target, 0.01, "eases to it")
	assert_eq(navigator.body, planet, "towards the selected planet")
	for i: int in 10:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		get_viewport().push_input(wheel, true)
	assert_eq(navigator.level, NavigatorStation.Level.BODY, "on to the globe")


func test_navigator_cannot_choose_while_the_ramp_is_down() -> void:
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	var navigator: NavigatorStation = await _use_navigator()
	var system: StarSystem = _voyage.settings.system
	navigator.show_body(system.bodies[0])
	var other: Region = system.bodies[0].regions[2]
	navigator.select(navigator.get_part(other))
	assert_true(navigator.activate(), "looking is fine")
	assert_false(navigator.choose_destination())
	assert_ne(_voyage.destination, _voyage.offer_for(other))


func test_flight_console_sets_course_for_the_destination() -> void:
	var console := _ship.get_node("Rooms/Upper/Cockpit/FlightConsole") as FlightStation
	await _move(console.use_point.global_position)
	assert_eq(_player.interact(), console.use_point)
	await wait_process_frames(1)
	var card := console.card_menu as FlightCard
	assert_false(console.can_launch(), "no destination yet")
	assert_false(card.press_primary())
	var offer: MissionBrief = _voyage.offers[1]
	_voyage.preview(offer)
	await wait_process_frames(1)
	assert_false(console.can_launch(), "only shown at the navigator")
	_voyage.choose(offer)
	await wait_process_frames(1)
	assert_true(console.can_launch())
	_send(&"interact")
	assert_eq(_voyage.brief, offer)
	assert_true(_ship.flight.is_flying())
	assert_false(console.can_launch(), "not again in flight")


func test_camera_frames_the_navigator() -> void:
	var navigator: NavigatorStation = await _use_navigator()
	var settings: Terminal = _ship.get_node("Rooms/Upper/Cabin1/Terminal") as Terminal
	assert_gt(navigator.view_height, settings.panel.view_height, "room for the hologram")
	assert_eq(WorldMenu.used_by(get_tree(), _player), navigator)


## Once the heat shield got another plate the hologram is built again, with the planet now
## reachable. Before it was ever shown there's nothing to build again.
func test_hologram_rebuilds_after_a_new_plate() -> void:
	var unshown := NavigatorStation.new()
	unshown.rebuild_hologram()
	unshown.free()
	var navigator: NavigatorStation = await _use_navigator()
	var locked: CelestialBody = null
	for body: CelestialBody in _voyage.settings.system.bodies:
		if not locked and body.kind == CelestialBody.Kind.PLANET and body.tier == 2:
			locked = body
	assert_false(navigator.is_reachable(locked))
	var before: StationPart = navigator.get_part(locked)
	_ship.heat_shield.install_next()
	var after: StationPart = navigator.get_part(locked)
	var reachable: bool = navigator.is_reachable(locked)
	assert_not_null(after)
	assert_ne(after, before, "built again")
	assert_true(reachable)


func _use_navigator() -> NavigatorStation:
	var navigator := _ship.get_node("Rooms/Upper/Bridge/Navigator") as NavigatorStation
	# Anywhere around the table.
	await _move(navigator.global_position + navigator.global_basis.z * 2.8)
	assert_eq(_player.interact(), navigator.use_point)
	await wait_process_frames(1)
	return navigator


## Presses and releases `action` as an input event.
func _send(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input(event)


func _move(target: Vector3) -> void:
	_player.global_position = target
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
