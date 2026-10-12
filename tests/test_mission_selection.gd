extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")
## In front of the mission console on the bridge (ship-local).
const AT_CONSOLE := Vector3(-61.9, 7.5, 2.9)

var _map: Node3D
var _player: Player
var _mission: Mission
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_mission = _map.get_node("Mission") as Mission
	_ship = _map.get_node("Ship") as Ship
	_ship.ramp_duration = 0.25
	watch_signals(_mission)
	await wait_physics_frames(2)


func test_offers_missions_from_easy_to_hard() -> void:
	var settings: MissionSettings = _mission.settings
	assert_eq(_mission.offers.size(), settings.offers)
	var difficulties: Array = []
	for offer: MissionBrief in _mission.offers:
		difficulties.append(offer.difficulty)
		assert_has(settings.biomes, offer.biome)
		assert_has(Array(settings.lengths), offer.length)
		assert_gt(offer.world_seed, 0)
		assert_ne(offer.location_name(), "")
	assert_eq(
		difficulties,
		[MissionBrief.Difficulty.EASY, MissionBrief.Difficulty.NORMAL, MissionBrief.Difficulty.HARD]
	)
	assert_null(_mission.brief, "none is picked at the start")


func test_ramp_needs_a_picked_mission() -> void:
	assert_false(_ship.ramp_button.enabled)
	_ship.ramp_button.use(_player)
	await wait_physics_frames(2)
	assert_eq(_mission.state, Mission.State.CLOSED)
	assert_eq(_ship.countdown_text, "No mission")
	assert_true(_mission.select(_mission.offers[0]))
	_mission.skip_flight()
	await wait_physics_frames(2)
	assert_true(_ship.ramp_button.enabled)
	var seconds: int = ceili(_mission.duration())
	assert_eq(_ship.countdown_text, "%d:%02d" % [floori(seconds / 60.0), seconds % 60])
	_ship.ramp_button.use(_player)
	assert_eq(_mission.state, Mission.State.OPEN)


func test_picking_flies_to_the_mission() -> void:
	var offer: MissionBrief = _mission.offers[2]
	var old_location: Node3D = _mission.location
	assert_true(_mission.select(offer))
	assert_eq(_mission.brief, offer)
	assert_signal_emitted_with_parameters(_mission, "selected", [offer])
	assert_eq(_mission.duration(), _mission.settings.duration * offer.length)
	assert_eq(_mission.time_left, _mission.duration())
	assert_true(_ship.flight.is_flying())
	_mission.skip_flight()
	assert_true(old_location.is_queued_for_deletion(), "a fresh outside world")
	assert_eq(_mission.location.name, &"Location")
	assert_ne(_mission.location, old_location)


func test_only_offered_missions_can_be_picked() -> void:
	var other := MissionBrief.new()
	assert_false(_mission.select(other))
	assert_null(_mission.brief)


func test_mission_is_locked_once_the_ramp_is_down() -> void:
	TEST_MAP.pick_mission(_map)
	assert_true(_mission.select(_mission.offers[1]), "another one can be picked before leaving")
	_mission.skip_flight()
	assert_eq(_mission.brief, _mission.offers[1])
	_ship.ramp_button.use(_player)
	assert_false(_mission.can_select())
	assert_false(_mission.select(_mission.offers[2]))
	assert_eq(_mission.brief, _mission.offers[1])
	_ship.ramp_button.use(_player)
	assert_eq(_mission.state, Mission.State.CLOSED, "the ramp went up again before leaving")
	assert_true(_mission.can_select())


func test_finished_mission_brings_new_offers() -> void:
	TEST_MAP.pick_mission(_map)
	var old_offers: Array[MissionBrief] = _mission.offers.duplicate()
	_ship.ramp_button.use(_player)
	await wait_physics_frames(ceili(_ship.ramp_duration * Engine.physics_ticks_per_second) + 2)
	await _move(_ship.to_global(Vector3(22.0, 0.0, 0.0)))
	assert_eq(_mission.state, Mission.State.RUNNING)
	await _move(_ship.to_global(Vector3(10.0, 2.5, 0.0)))
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_null(_mission.brief)
	assert_eq(_mission.offers.size(), old_offers.size())
	for offer: MissionBrief in _mission.offers:
		assert_does_not_have(old_offers, offer)
	assert_true(_mission.can_select())


func test_picking_only_previews_until_course_is_set() -> void:
	var offer: MissionBrief = _mission.offers[1]
	var old_location: Node3D = _mission.location
	assert_true(_mission.preview(offer))
	assert_eq(_mission.previewed, offer)
	assert_null(_mission.brief)
	assert_signal_not_emitted(_mission, "selected")
	assert_false(_ship.flight.is_flying())
	assert_eq(_mission.location, old_location)
	assert_true(_mission.preview(_mission.offers[2]), "another one to compare")
	assert_true(_mission.confirm())
	assert_eq(_mission.brief, _mission.offers[2])


func test_hologram_marks_the_ore_fields() -> void:
	var table: HoloTable = _ship.get_node("Rooms/Upper/Bridge/HoloTable") as HoloTable
	TEST_MAP.pick_mission(_map)
	var ores: Array[OreNode] = []
	for ore: OreNode in get_tree().get_nodes_in_group(OreNode.GROUP):
		if _mission.location.is_ancestor_of(ore):
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


func test_console_on_the_bridge_picks_missions() -> void:
	var terminal: Terminal = _ship.get_node("Rooms/Upper/Bridge/MissionTerminal") as Terminal
	await _move(_ship.to_global(AT_CONSOLE))
	assert_eq(_player.interact(), terminal)
	var menu := terminal.panel.content as MissionMenu
	assert_not_null(menu)
	await wait_process_frames(2)
	assert_eq(menu.mission, _mission)
	var button: Button = menu.get_button(_mission.offers[1])
	assert_not_null(button)
	assert_false(button.disabled)
	var set_course: Button = menu.get_set_course_button()
	assert_true(set_course.disabled, "nothing picked yet")
	button.pressed.emit()
	assert_eq(_mission.previewed, _mission.offers[1])
	assert_null(_mission.brief, "only shown on the hologram")
	await wait_process_frames(1)
	assert_true(button.button_pressed, "the picked mission shows")
	assert_false(menu.get_button(_mission.offers[0]).button_pressed)
	assert_false(set_course.disabled)
	set_course.pressed.emit()
	assert_eq(_mission.brief, _mission.offers[1])
	assert_true(_ship.flight.is_flying())
	await wait_process_frames(1)
	assert_true(button.disabled, "no picking in flight")
	assert_true(set_course.disabled)


func test_console_locks_while_the_ramp_is_down() -> void:
	var terminal: Terminal = _ship.get_node("Rooms/Upper/Bridge/MissionTerminal") as Terminal
	var menu := terminal.panel.content as MissionMenu
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_process_frames(2)
	assert_true(menu.get_button(_mission.offers[1]).disabled)


func test_camera_frames_console_and_hologram() -> void:
	var terminal: Terminal = _ship.get_node("Rooms/Upper/Bridge/MissionTerminal") as Terminal
	var focus: Node3D = _ship.get_node("Rooms/Upper/Bridge/MissionView") as Node3D
	assert_eq(terminal.panel.view_focus, focus)
	assert_eq(terminal.panel.get_view_center(), focus.global_position)
	var settings: Terminal = _ship.get_node("Rooms/Upper/Cabin1/Terminal") as Terminal
	assert_gt(terminal.panel.view_height, settings.panel.view_height, "room for the hologram")


func _move(target: Vector3) -> void:
	_player.global_position = target
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
