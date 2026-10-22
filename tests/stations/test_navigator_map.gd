extends GutTest
## The navigator as a campaign map (see GAME_DESIGN.md, Mission selection): every body fits on the
## table, name plates with signature ores ("?" while out of reach), the ship's marker and routes,
## region plates with danger pips and ores on globes colored by biome, the tier on the card, and
## setting a destination from the globe zooming into its landing site.

const TEST_MAP := preload("res://tests/support/test_map.gd")

var _map: Node3D
var _player: Player
var _mission: Mission
var _navigator: NavigatorStation
var _system: StarSystem


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_mission = _map.get_node("Mission") as Mission
	_navigator = _map.get_node("Ship/Rooms/Upper/Bridge/Navigator") as NavigatorStation
	_system = _mission.settings.system
	await wait_physics_frames(2)
	_navigator.open(_player)
	await wait_process_frames(2)


## The star's orbits spread evenly between the innermost and the outermost one, in their order;
## moons stay close to their planet.
func test_every_body_fits_on_the_table() -> void:
	var around_star: Array[CelestialBody] = []
	for body: CelestialBody in _system.bodies:
		var orbit: float = _navigator.display_orbit(body)
		if body.orbits:
			assert_lt(orbit, _navigator.inner_orbit, body.display_name + " near its planet")
		else:
			assert_between(orbit, _navigator.inner_orbit, _navigator.outer_orbit, body.display_name)
			around_star.append(body)
	around_star.sort_custom(
		func(a: CelestialBody, b: CelestialBody) -> bool: return a.orbit_radius < b.orbit_radius
	)
	var step: float = (_navigator.outer_orbit - _navigator.inner_orbit) / (around_star.size() - 1)
	for i: int in around_star.size():
		var expected: float = _navigator.inner_orbit + step * i
		assert_almost_eq(_navigator.display_orbit(around_star[i]), expected, 0.001)


## A plate per body with its name and signature ore; "?" for one that can't be reached yet.
func test_body_plates_hide_what_cannot_be_reached() -> void:
	var plates: Array[HoloPlate] = _navigator.get_plates()
	assert_eq(plates.size(), _system.bodies.size())
	for body: CelestialBody in _system.bodies:
		var plate: HoloPlate = _plate(plates, tr(body.display_name))
		assert_not_null(plate, body.display_name)
		if not plate:
			continue
		var expected: Array[OreType] = []
		for ore_type: OreType in body.signature_ores:
			expected.append(ore_type if body.is_reachable(1) else null)
		assert_eq(plate.get_ores(), expected, body.display_name)


## The ship's marker stands at the body it's at; routes lead to every other reachable body, the
## destination's brighter. Setting course moves the ship there.
func test_routes_lead_from_the_ship() -> void:
	var torvane: CelestialBody = _body("Torvane")
	var lisk: CelestialBody = _body("Lisk")
	assert_eq(_navigator.ship_body(), torvane, "the first planet before any flight")
	assert_eq(_routes(), {lisk: false}, "the only other body it can go to")
	assert_true(_mission.choose(_mission.offer_for(lisk.regions[0])))
	assert_eq(_routes(), {lisk: true}, "the destination's route")
	assert_true(_mission.confirm())
	assert_eq(_mission.at_body, lisk)
	assert_eq(_navigator.ship_body(), lisk)
	assert_eq(_routes(), {torvane: false}, "from the moon now")


## Each region of a globe has a plate: its name, its danger's pips and its ores (the signature
## ores of a body out of reach as "?"); the globe fills regions in their biome's color.
func test_region_plates_show_danger_and_ores() -> void:
	for body: CelestialBody in [_body("Torvane"), _body("Vehra")]:
		_navigator.show_body(body)
		await wait_process_frames(2)
		var plates: Array[HoloPlate] = _navigator.get_plates()
		assert_eq(plates.size(), body.regions.size(), body.display_name)
		for region: Region in body.regions:
			var plate: HoloPlate = _plate(plates, tr(region.display_name))
			assert_not_null(plate, region.display_name)
			if not plate:
				continue
			assert_eq(plate.get_lit_pips(), region.danger + 1, region.display_name)
			var ores: Array[OreType] = plate.get_ores()
			assert_eq(ores, _navigator.shown_ores(region), region.display_name)
			for ore_type: OreType in body.signature_ores:
				assert_eq(ore_type in ores, body.is_reachable(1), region.display_name)
			assert_eq(ores.has(null), not body.is_reachable(1), region.display_name)
		var globe := _navigator.get_node("View/Globe/Sphere") as MeshInstance3D
		var fills: PackedColorArray = (
			(globe.material_override as ShaderMaterial).get_shader_parameter(&"region_colors")
		)
		for i: int in body.regions.size():
			assert_eq(Color(fills[i], 1.0), body.regions[i].biome.map_color, "biome color")


## The card shows the tier of a body and of a region's body, and a locked planet's signature ore
## as "?".
func test_card_shows_the_tier() -> void:
	var card := _navigator.card_menu as NavigatorCard
	var vehra: CelestialBody = _body("Vehra")
	_navigator.select(_navigator.get_part(vehra))
	await wait_process_frames(1)
	assert_string_ends_with((card.get_node("%Subtitle") as Label).text, "Tier 2")
	var ores: Array[Node] = card.get_node("%Ores").get_children()
	assert_eq(ores.size(), 1)
	assert_eq((ores[0] as Label).text if ores[0] is Label else "", "?", "not known yet")
	_navigator.show_body(_body("Torvane"))
	_navigator.select(_navigator.get_part(_body("Torvane").regions[0]))
	await wait_process_frames(1)
	assert_string_ends_with((card.get_node("%Subtitle") as Label).text, "Tier 1")
	assert_true((card.get_node("%Danger") as Label).visible)


## "Set as destination" on the globe chooses the region and zooms into its landing site.
func test_setting_the_destination_zooms_into_the_landing_site() -> void:
	var card := _navigator.card_menu as NavigatorCard
	var torvane: CelestialBody = _body("Torvane")
	_navigator.show_body(torvane)
	var region: Region = torvane.regions[1]
	_navigator.select(_navigator.get_part(region))
	await wait_process_frames(1)
	(card.get_node("%Choose") as Button).pressed.emit()
	assert_eq(_mission.destination, _mission.offer_for(region))
	assert_eq(_navigator.level, NavigatorStation.Level.REGION, "zooms in")
	assert_eq(_mission.previewed, _mission.offer_for(region), "its landing site on the table")
	await wait_seconds(1.0)
	assert_eq(_navigator.zoom, 2.0, "smoothly")
	assert_eq(_navigator.selected.item, region)


func _body(body_name: String) -> CelestialBody:
	for body: CelestialBody in _system.bodies:
		if body.display_name == body_name:
			return body
	return null


func _plate(plates: Array[HoloPlate], text: String) -> HoloPlate:
	for plate: HoloPlate in plates:
		if plate.get_text() == text:
			return plate
	return null


## The routes drawn: body -> whether it's the destination's.
func _routes() -> Dictionary:
	var routes: Dictionary = {}
	for route: Dictionary in _navigator.get_routes():
		routes[route["body"]] = route["chosen"]
	return routes
