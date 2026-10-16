extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")
const ALIEN: PackedScene = preload("res://game/aliens/alien.tscn")

var _map: Node3D
var _player: Player
var _camera: Camera3D


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_camera = get_viewport().get_camera_3d()
	# Outside, where the weapon is drawn.
	var ship: Ship = _map.get_node("Ship")
	_player.global_position = ship.to_global(Vector3(22.0, 0.0, 0.0))
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)


func after_each() -> void:
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)


func test_cursor_over_alien_locks_it() -> void:
	var alien: Alien = await _alien_at(_screen_right() * 6.0)
	_player.aim_at_screen_position(_camera, _camera.unproject_position(alien.get_aim_point()))
	assert_eq(_player.aim_target, alien)
	assert_almost_eq(_player.aim_direction.dot(_screen_right()), 1.0, 0.01)


func test_cursor_close_to_alien_locks_far_one_does_not() -> void:
	var alien: Alien = await _alien_at(_screen_right() * 6.0)
	var on_screen: Vector2 = _camera.unproject_position(alien.get_aim_point())
	var height: float = get_viewport().get_visible_rect().size.y
	var lock: float = _player.settings.target_lock_radius
	_player.aim_at_screen_position(_camera, on_screen + Vector2.UP * height * lock * 0.8)
	assert_eq(_player.aim_target, alien, "close")
	# Once locked, it holds a bit farther away.
	var release: float = _player.settings.target_release_radius
	_player.aim_at_screen_position(_camera, on_screen + Vector2.UP * height * release * 0.9)
	assert_eq(_player.aim_target, alien, "held")
	_player.aim_at_screen_position(_camera, on_screen + Vector2.UP * height * release * 1.5)
	assert_null(_player.aim_target, "let go")


func test_stick_locks_alien_close_to_its_direction() -> void:
	var alien: Alien = await _alien_at(_screen_right() * 8.0)
	var angle: float = deg_to_rad(_player.settings.stick_lock_angle)
	_player.aim_with_stick(_screen_right().rotated(Vector3.UP, angle * 0.5))
	assert_eq(_player.aim_target, alien)
	_player.aim_with_stick(_screen_right().rotated(Vector3.UP, angle * 2.0))
	assert_null(_player.aim_target)


func test_dead_alien_is_let_go() -> void:
	var alien: Alien = await _alien_at(_screen_right() * 6.0)
	_player.aim_with_stick(_screen_right())
	assert_eq(_player.aim_target, alien)
	alien.take_damage(alien.health)
	_player.aim_with_stick(_screen_right())
	assert_null(_player.aim_target)


## Locked on an alien up on a ledge, shots fly up at it and hit.
func test_locked_shots_hit_alien_above() -> void:
	var ledge := StaticBody3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 3.0, 2.0)
	var shape := CollisionShape3D.new()
	shape.shape = box
	ledge.add_child(shape)
	_map.add_child(ledge)
	ledge.global_position = _player.global_position + _screen_right() * 8.0 + Vector3.UP * 1.5
	var alien: Alien = await _alien_at(_screen_right() * 8.0 + Vector3.UP * 3.0)
	var health: float = alien.health
	Input.action_press(&"aim_right")
	Input.action_press(&"attack")
	await wait_physics_frames(2)
	assert_eq(_player.aim_target, alien)
	await wait_physics_frames(30)
	assert_lt(alien.health, health, "hit")


func test_marker_shows_under_locked_alien() -> void:
	var marker: Node3D = _player.get_node("TargetMarker")
	var alien: Alien = await _alien_at(_screen_right() * 6.0)
	Input.action_press(&"aim_right")
	await wait_frames(3)
	assert_true(marker.visible)
	assert_almost_eq(
		Vector2(marker.global_position.x, marker.global_position.z),
		Vector2(alien.global_position.x, alien.global_position.z),
		Vector2.ONE * 0.01
	)
	Input.action_release(&"aim_right")
	Input.action_press(&"move_left")
	await wait_frames(3)
	assert_false(marker.visible)


## An alien that stays where it is (doesn't notice the player).
func _alien_at(offset: Vector3) -> Alien:
	var alien := ALIEN.instantiate() as Alien
	alien.settings = alien.settings.duplicate() as AlienSettings
	alien.settings.detection_range = 0.0
	_map.add_child(alien)
	alien.global_position = _player.global_position + offset
	alien.reset_physics_interpolation()
	await wait_physics_frames(2)
	return alien


func _screen_right() -> Vector3:
	return IsoInput.camera_relative(Vector2.RIGHT, _camera.global_basis)
