extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")
const PROJECTILE: PackedScene = preload("res://game/weapons/projectile.tscn")

var _map: Node3D
var _player: Player


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	# Weapons are holstered inside the ship, where the player starts.
	var ship: Ship = _map.get_node("Ship")
	_player.global_position = ship.to_global(Vector3(22.0, 0.0, 0.0))
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)


func after_each() -> void:
	Input.action_release(&"attack")


func test_no_attack_inside_ship() -> void:
	var ship: Ship = _map.get_node("Ship")
	_player.global_position = ship.to_global(Vector3(10.0, 2.5, 0.0))
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	assert_false(_player.weapon_allowed)
	assert_false(_player.weapon.visible, "weapon is holstered")
	var fired: Array[Projectile] = _record_projectiles()
	Input.action_press(&"attack")
	await wait_physics_frames(10)
	assert_eq(fired.size(), 0)


func test_player_equips_first_loadout_weapon() -> void:
	assert_eq(_player.get_weapon_type(), _player.loadout.get_weapon(0))
	assert_is(_player.weapon, RangedWeapon)
	assert_eq(_player.weapon.get_parent().name, &"WeaponMount")


func test_holding_attack_fires_at_attack_rate() -> void:
	var fired: Array[Projectile] = _record_projectiles()
	Input.action_press(&"attack")
	await wait_physics_frames(Engine.physics_ticks_per_second)
	var rate: float = (_player.weapon as RangedWeapon).settings.attack_rate
	assert_between(float(fired.size()), rate, rate + 1.0)


func test_no_attack_without_input() -> void:
	var fired: Array[Projectile] = _record_projectiles()
	await wait_physics_frames(30)
	assert_eq(fired.size(), 0)


func test_projectile_flies_along_aim_direction() -> void:
	var fired: Array[Projectile] = _record_projectiles()
	Input.action_press(&"attack")
	await wait_physics_frames(1)
	Input.action_release(&"attack")
	assert_eq(fired.size(), 1)
	var projectile: Projectile = fired[0]
	var start: Vector3 = projectile.global_position
	await wait_physics_frames(5)
	var flown: Vector3 = projectile.global_position - start
	assert_almost_eq(flown.normalized().dot(_player.aim_direction), 1.0, 0.001)


## Standing right at a rock puts the muzzle inside it; the shot must still stop there.
func test_projectile_from_muzzle_inside_collider_is_blocked() -> void:
	var rock: Node3D = _map.get_node("Location/Rocks/RockA")
	_player.global_position = rock.global_position + Vector3(0.0, -1.0, 1.7)
	_player.reset_physics_interpolation()
	await wait_physics_frames(2)
	var fired: Array[Projectile] = _record_projectiles()
	Input.action_press(&"attack")
	await wait_physics_frames(1)
	Input.action_release(&"attack")
	await wait_physics_frames(2)
	assert_eq(fired.size(), 1)
	for projectile: Projectile in fired:
		assert_false(is_instance_valid(projectile), "projectile passed through the rock")


func test_projectile_stops_at_first_collider() -> void:
	var rock: Node3D = _map.get_node("Location/Rocks/RockA")
	var projectile: Projectile = _spawn(
		rock.global_position + Vector3(0.0, 0.0, 5.0), Vector3.FORWARD
	)
	var hits: Array[Object] = []
	projectile.hit.connect(func(collider: Object, _at: Vector3) -> void: hits.append(collider))
	await wait_physics_frames(20)
	assert_eq(hits, [rock] as Array[Object])
	assert_false(is_instance_valid(projectile), "projectile still exists after hitting")


func test_projectile_disappears_after_range() -> void:
	var projectile: Projectile = _spawn(Vector3(0.0, 2.0, 0.0), Vector3.UP, 3.0)
	await wait_physics_frames(10)
	assert_false(is_instance_valid(projectile), "projectile still exists after its range")


func _record_projectiles() -> Array[Projectile]:
	var fired: Array[Projectile] = []
	_map.child_entered_tree.connect(
		func(node: Node) -> void:
			if node is Projectile:
				fired.append(node as Projectile)
	)
	return fired


## 30 m/s, so it crosses 5 m in 10 physics frames.
func _spawn(at: Vector3, direction: Vector3, max_distance: float = 25.0) -> Projectile:
	var projectile := PROJECTILE.instantiate() as Projectile
	projectile.velocity = direction * 30.0
	projectile.max_distance = max_distance
	_map.add_child(projectile)
	projectile.global_position = at
	return projectile
