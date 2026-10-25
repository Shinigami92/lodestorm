extends GutTest
## The kit's shell aboard (so far the armory with its stretch of corridor): its materials and room
## looks, the doors that open before anyone gets there, the neon signs.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")

var _map: Node3D
var _player: Player
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func test_shell_uses_the_shell_materials() -> void:
	var shell := _ship.get_node("Hull/ShellHull") as ShipShell
	var floor_mesh := shell.find_child("Armory", true, false) as MeshInstance3D
	assert_not_null(floor_mesh, "the armory's floor is the kit's")
	var used: Array[Material] = []
	for i: int in floor_mesh.mesh.get_surface_count():
		used.append(floor_mesh.get_surface_override_material(i))
	assert_has(used, ShipShell.MATERIALS["ShellPlate"])
	var look: RoomLook = ShipShell.LOOKS.get_look(&"Armory")
	assert_eq(floor_mesh.get_instance_shader_parameter(&"room_tint") as Color, look.floor_tint)
	# The accents are an object of their own: instance parameters share slots within one object, so
	# the floor would take the accent's color.
	var accent := shell.find_child("ArmoryAccent", true, false) as MeshInstance3D
	assert_not_null(accent)
	assert_eq(accent.get_instance_shader_parameter(&"accent") as Color, look.accent_color)
	assert_eq(typeof(floor_mesh.get_instance_shader_parameter(&"accent")), TYPE_NIL)


func test_shell_is_cut_away_with_its_group() -> void:
	var cut := _ship.get_node("Hull/LowerCut/ShellLowerCut") as ShipShell
	var mesh := cut.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	await _move(_ship.to_global(Vector3(-12.0, 2.7, -6.0)))
	assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)


## Cabins and crew cabins share their look; a name's trailing number is dropped.
func test_room_looks_by_name() -> void:
	assert_same(ShipShell.LOOKS.get_look(&"Cabin3"), ShipShell.LOOKS.get_look(&"Cabin"))
	assert_not_null(ShipShell.LOOKS.get_look(&"Crew7"))
	assert_null(ShipShell.LOOKS.get_look(&"Nowhere"))
	for room: StringName in [&"Armory", &"LowerCorridor", &"CargoBay", &"SpecimenLab"]:
		assert_not_null(ShipShell.LOOKS.get_look(room), room)


func test_door_opens_before_a_player_arrives() -> void:
	var door := _ship.get_node("Hull/CargoWallLowerLintelDoor") as ShipDoor
	await _move(_ship.to_global(Vector3(-15.0, 2.7, -8.0)))
	await wait_physics_frames(int(door.close_delay * 60.0) + 40)
	assert_eq(door.openness, 0.0, "nobody near: closed")
	# Running at it: open by the time the player covers the last meter.
	var run_seconds: float = (door.reach - 1.0) / _player.settings.move_speed
	await _move(door.global_position + door.global_basis.z * (door.reach - 0.2))
	await wait_physics_frames(ceili(run_seconds * 60.0))
	assert_eq(door.openness, 1.0)


func test_door_stays_open_a_moment_then_closes() -> void:
	var door := _ship.get_node("Hull/CargoWallLowerLintelDoor") as ShipDoor
	await _move(door.global_position + door.global_basis.z * 2.0)
	await wait_physics_frames(40)
	await _move(_ship.to_global(Vector3(-15.0, 2.7, -8.0)))
	await wait_physics_frames(int(door.close_delay * 60.0 * 0.5))
	assert_eq(door.openness, 1.0, "still open right after leaving")
	await wait_physics_frames(int(door.close_delay * 60.0) + 40)
	assert_eq(door.openness, 0.0)


## Doors never block: nothing in them collides.
func test_door_has_no_collision() -> void:
	var door := _ship.get_node("Hull/CargoWallLowerLintelDoor") as ShipDoor
	assert_eq(door.find_children("*", "CollisionObject3D", true, false).size(), 0)
	assert_eq(door.find_children("*", "CollisionShape3D", true, false).size(), 0)


## Every room's door comes from the layout (not the ramp's or the lifts' gates), and every room has
## its lamps and its reflections.
func test_doors_and_lights_from_the_layout() -> void:
	var hull := _ship.get_node("Hull")
	var doors: Array[Node] = hull.find_children("*Door", "ShipDoor", true, false)
	assert_eq(doors.size(), 27)
	assert_null(hull.find_child("DoorLintelDoor", true, false), "the ramp keeps its own door")
	for room: String in ["Cockpit", "Bridge", "Armory", "Cabin1", "Crew8", "MessHall", "CargoBay"]:
		assert_not_null(hull.find_child(room + "Lamp1", true, false), room)
		assert_not_null(hull.find_child(room + "Reflections", true, false), room)


## Every room's name is a neon sign on a wall in the room's accent color (no paint on the floor),
## and the guides are signs with arrows.
func test_room_names_and_guides_are_signs() -> void:
	for deck: Node in _ship.get_node("Rooms").get_children():
		for room: Node in [deck] + deck.get_children():
			var sign_node: Node = room.get_node_or_null("Sign")
			if not sign_node:
				continue
			var neon := sign_node as NeonSign
			assert_not_null(neon, "%s's name is a neon sign" % room.name)
			if neon:
				var look: RoomLook = ShipShell.LOOKS.get_look(room.name)
				assert_eq(neon.color, look.accent_color, String(room.name))
	assert_eq(_ship.find_children("*", "FloorGuide", true, false).size(), 0)
	for guides: String in ["Rooms/Lower/Guides", "Rooms/Upper/Guides"]:
		for guide: Node in _ship.get_node(guides).get_children():
			assert_ne((guide as NeonSign).arrow, NeonSign.Arrow.NONE, guide.name)


## A sign's backing grows with its translated text.
func test_neon_sign_fits_its_text() -> void:
	var neon := _ship.get_node("Rooms/Lower/Armory/Sign") as NeonSign
	var width: float = neon.get_width()
	assert_gt(width, 1.0)
	TranslationServer.set_locale("de")
	assert_ne(neon.get_width(), width, "Waffenkammer is longer than Armory")
	TranslationServer.set_locale("en")
	assert_almost_eq(neon.get_width(), width, 0.001)


func _move(target: Vector3) -> void:
	_player.global_position = target
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
