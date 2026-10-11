extends GutTest

const TEST_MAP: PackedScene = preload("res://scenes/maps/test_map.tscn")

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
	await wait_physics_frames(2)


func test_ramp_faces_screen_right() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var screen_right: Vector3 = IsoInput.camera_relative(Vector2.RIGHT, camera.global_basis)
	assert_almost_eq(_ship.global_basis.x.dot(screen_right), 1.0, 0.001)
	var to_door: Vector3 = _ship.get_boarding_position() - _ship.global_position
	assert_gt(to_door.dot(screen_right), 0.0)


func test_camera_sees_inside_while_aboard() -> void:
	var roof: GeometryInstance3D = _ship.get_node("Hull/Cutaway/Roof")
	assert_eq(roof.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	await _move(_player, _outside())
	assert_eq(roof.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


func test_every_room_is_aboard() -> void:
	for room: Node3D in _ship.get_node("Rooms").get_children():
		await _move(_player, _outside())
		await _move(_player, room.global_position)
		assert_true(_ship.is_aboard(_player), room.name)


## The doorways line up along the corridor, so players walk from the cargo bay through the bridge
## to the far end of the ship.
func test_corridor_runs_through_the_ship() -> void:
	var up := Vector3.UP * 2.5
	var cargo_bay: Vector3 = _room("CargoBay").global_position + up
	var far_end: Vector3 = _room("WestCorridor").global_position + up
	assert_eq(_ray(cargo_bay, far_end), {}, "doorways")
	var beside: Vector3 = _ship.global_basis.z * -4.0
	assert_ne(_ray(cargo_bay + beside, far_end + beside), {}, "walls between the rooms")


## Walls between the camera and a room only cast shadows while players are aboard; a low stub of
## them stays visible.
func test_inner_walls_facing_camera_are_cut_down() -> void:
	var cut: GeometryInstance3D = _ship.get_node("Hull/Cutaway/WestCorridorBack1")
	assert_eq(cut.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	var stub: MeshInstance3D = _ship.get_node("Hull/WestCorridorBack1Stub")
	assert_eq(stub.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	assert_lt(stub.get_aabb().size.y, 1.5)


func test_dead_respawn_in_medical_bay() -> void:
	var medical_bay: Vector3 = _room("MedicalBay").global_position
	assert_almost_eq(_ship.get_respawn_position().distance_to(medical_bay), 0.0, 3.0)


func test_ship_shows_time_left() -> void:
	var countdown: Label3D = _ship.get_node("Countdown")
	_mission.time_left = 200.4
	await wait_process_frames(1)
	assert_eq(countdown.text, "3:21")
	assert_eq(_ship.beacon_color, Ship.COLOR_CALM)


func test_beacon_shows_how_urgent_it_is() -> void:
	await _open()
	await _move(_player, _outside())
	_mission.time_left = _mission.settings.duration * 0.4
	await wait_process_frames(1)
	assert_eq(_ship.beacon_color, Ship.COLOR_HALF)
	_mission.time_left = _mission.settings.warning_time * 0.5
	await wait_process_frames(1)
	assert_eq(_ship.beacon_color, Ship.COLOR_WARNING)
	await _move(_player, _inside())
	await wait_process_frames(1)
	assert_eq(_ship.beacon_color, Ship.COLOR_RETURNED)


func test_pointer_hides_near_ship() -> void:
	await wait_physics_frames(5)
	assert_false(_pointer().visible)


func test_pointer_hides_inside_ship() -> void:
	await _move(_player, _ship.to_global(Vector3(-12.0, 1.0, 0.0)))
	var to_door: Vector3 = _ship.get_boarding_position() - _player.global_position
	assert_gt(to_door.length(), _pointer().min_distance, "far from the door")
	assert_false(_pointer().visible)


func test_pointer_shows_way_back_from_far_away() -> void:
	await _move(_player, _ship.to_global(Vector3(45.0, 0.0, 0.0)))
	_mission.time_left = _mission.settings.warning_time * 0.5
	await wait_physics_frames(2)
	await wait_process_frames(1)
	var pointer: ShipPointer = _pointer()
	assert_true(pointer.visible)
	var to_ship: Vector3 = _ship.get_boarding_position() - pointer.global_position
	to_ship.y = 0.0
	assert_almost_eq((-pointer.global_basis.z).dot(to_ship.normalized()), 1.0, 0.001)
	var arrow: MeshInstance3D = pointer.get_node("Arrow")
	var material: StandardMaterial3D = arrow.material_override
	assert_eq(Color(material.albedo_color, 1.0), Ship.COLOR_WARNING)
	var countdown: Label3D = pointer.get_node("Countdown")
	assert_eq(countdown.text, (_ship.get_node("Countdown") as Label3D).text)
	assert_eq(countdown.text, "0:30")
	assert_eq(Color(countdown.modulate, 1.0), Ship.COLOR_WARNING)


func _pointer() -> ShipPointer:
	return _player.get_node("ShipPointer") as ShipPointer


## Presses the ramp button and waits until the ramp is down.
func _open() -> void:
	_ship.ramp_button.use(_player)
	await _wait_for_ramp()


func _wait_for_ramp() -> void:
	await wait_physics_frames(ceili(_ship.ramp_duration * Engine.physics_ticks_per_second) + 2)


## Inside the ship, near the door.
func _inside() -> Vector3:
	return _ship.to_global(Vector3(10.0, 1.0, 0.0))


## On the ground right of the ramp.
func _outside() -> Vector3:
	return _ship.to_global(Vector3(22.0, 0.0, 0.0))


func _room(room_name: String) -> Node3D:
	return _ship.get_node("Rooms/" + room_name) as Node3D


## What a ray from `from` to `to` hits, ignoring the player.
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	return _ship.get_world_3d().direct_space_state.intersect_ray(query)


func _move(player: Player, target: Vector3) -> void:
	player.global_position = target
	player.reset_physics_interpolation()
	await wait_physics_frames(5)
