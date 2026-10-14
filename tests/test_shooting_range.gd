extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")

var _map: Node3D
var _player: Player
var _ship: Ship
var _range: Node3D


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	_range = _ship.get_node("Rooms/Lower/ShootingRange")
	await wait_physics_frames(2)


func test_weapons_work_only_in_the_range() -> void:
	assert_false(_player.weapon_allowed, "cargo bay")
	await _move(_player, _range.global_position)
	assert_true(_player.weapon_allowed, "shooting range")
	var corridor: Node3D = _ship.get_node("Rooms/Lower/LowerCorridor")
	await _move(_player, corridor.global_position)
	assert_false(_player.weapon_allowed, "corridor")


## Shots can't leave the range through its door, but players walk through it.
func test_barrier_keeps_shots_inside() -> void:
	var barrier: StaticBody3D = _range.get_node("Barrier")
	var inside: Vector3 = barrier.global_position - _ship.global_basis.z * 2.0
	var outside: Vector3 = barrier.global_position + _ship.global_basis.z * 2.0
	var query := PhysicsRayQueryParameters3D.create(inside, outside)
	var hit: Object = _ship.get_world_3d().direct_space_state.intersect_ray(query).get(&"collider")
	assert_eq(hit, barrier)
	assert_eq(_player.collision_mask & barrier.collision_layer, 0)


func test_shots_hit_the_targets() -> void:
	var target: StaticBody3D = _range.get_node("Target2")
	var from: Vector3 = target.global_position - _ship.global_basis.x * 20.0
	var query := PhysicsRayQueryParameters3D.create(from, target.global_position)
	var hit: Object = _ship.get_world_3d().direct_space_state.intersect_ray(query).get(&"collider")
	assert_eq(hit, target)


## Trying the weapons costs nothing: reloads in the range come from the ship's stock.
func test_reloads_in_the_range_spend_no_ore() -> void:
	var cyan: OreType = load("res://scenes/mining/ores/ore_cyan.tres")
	_player.add_cargo(cyan, 10.0)
	await _move(_player, _range.global_position)
	assert_true(_player.ammo_free)
	var blaster := _player.weapon as RangedWeapon
	blaster.rounds = 1
	Input.action_press(&"attack")
	await wait_physics_frames(2)
	Input.action_release(&"attack")
	assert_true(blaster.reloading, "the empty magazine reloads")
	blaster.reload_elapsed = blaster.reload_duration
	await wait_physics_frames(1)
	assert_eq(blaster.rounds, blaster.capacity())
	assert_eq(_player.cargo[cyan], 10.0)


## In the range the camera frames the whole room instead of following the player.
func test_camera_frames_the_range() -> void:
	var rig: IsoCameraRig = _map.get_node("IsoCameraRig")
	var zone: CameraZone = _range.get_node("CameraZone")
	await _move(_player, _range.global_position - _ship.global_basis.x * 10.0)
	await wait_seconds(1.5)
	assert_almost_eq(rig.global_position.distance_to(zone.focus_position()), 0.0, 0.5)


func _move(player: Player, target: Vector3) -> void:
	player.global_position = target
	player.reset_physics_interpolation()
	await wait_physics_frames(5)
