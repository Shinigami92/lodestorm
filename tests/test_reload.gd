extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const BLASTER: WeaponType = preload("res://scenes/weapons/types/blaster.tres")
const SHOTGUN: WeaponType = preload("res://scenes/weapons/types/shotgun.tres")
const HAMMER: WeaponType = preload("res://scenes/weapons/types/hammer.tres")
const CYAN: OreType = preload("res://scenes/mining/ores/ore_cyan.tres")
const GREEN: OreType = preload("res://scenes/mining/ores/ore_green.tres")
const VIOLET: OreType = preload("res://scenes/mining/ores/ore_violet.tres")

var _arena: Node3D
var _player: Player
var _fired: Array[Projectile] = []


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_add_floor()
	_player = _add_player(Vector3.ZERO)
	_player.arsenal.unlock(SHOTGUN)
	_fired.clear()
	_arena.child_entered_tree.connect(_on_child_entered)
	await wait_physics_frames(1)


func after_each() -> void:
	for action: StringName in [&"attack", &"interact", &"move_left"]:
		Input.action_release(action)


func test_magazine_reload_throws_away_the_rest_and_pays_the_commonest_ore_first() -> void:
	var blaster := _blaster()
	blaster.rounds = 20
	_player.add_cargo(GREEN, 10.0)
	_player.add_cargo(CYAN, 5.0)
	assert_true(_player.reload())
	assert_true(blaster.reloading)
	assert_eq(blaster.rounds, 0, "the rounds left in the magazine are lost")
	await _finish_reload(blaster)
	assert_false(blaster.reloading)
	assert_eq(blaster.rounds, blaster.capacity())
	# A full magazine costs 24 * 0.25 = 6: all 5 cyan, then 1 / 1.25 = 0.8 green.
	assert_almost_eq(_player.cargo[CYAN], 0.0, 0.001)
	assert_almost_eq(_player.cargo[GREEN], 9.2, 0.001)


func test_magazine_reload_loads_what_the_ore_pays() -> void:
	var blaster := _blaster()
	blaster.rounds = 10
	_player.add_cargo(CYAN, 2.0)
	assert_false(_player.reload(), "8 rounds wouldn't be more than the 10 loaded")
	assert_eq(blaster.rounds, 10)
	blaster.rounds = 0
	await _finish_reload(blaster)
	assert_eq(blaster.rounds, 8)
	assert_almost_eq(_player.cargo[CYAN], 0.0, 0.001)


func test_empty_weapon_reloads_by_itself() -> void:
	var blaster := _blaster()
	blaster.rounds = 1
	_player.add_cargo(CYAN, 100.0)
	await _attack_once()
	assert_eq(blaster.rounds, 0)
	assert_true(blaster.reloading, "the last shot starts a reload")


func test_timing_press_within_the_window_finishes_the_reload() -> void:
	var blaster := _blaster()
	blaster.rounds = 0
	_player.add_cargo(CYAN, 100.0)
	assert_true(_player.reload())
	var settings: RangedWeaponSettings = blaster.settings
	blaster.reload_elapsed = (
		(settings.sweet_spot_start + settings.sweet_spot_width * 0.5) * (settings.reload_time)
	)
	watch_signals(blaster)
	assert_true(_player.reload())
	assert_signal_emitted_with_parameters(blaster, "reload_timed", [true])
	assert_false(blaster.reloading)
	assert_eq(blaster.rounds, blaster.capacity())


func test_timing_press_outside_the_window_takes_longer() -> void:
	var blaster := _blaster()
	blaster.rounds = 0
	_player.add_cargo(CYAN, 100.0)
	_player.reload()
	var settings: RangedWeaponSettings = blaster.settings
	blaster.reload_elapsed = settings.sweet_spot_start * 0.5 * settings.reload_time
	watch_signals(blaster)
	assert_true(_player.reload())
	assert_signal_emitted_with_parameters(blaster, "reload_timed", [false])
	assert_true(blaster.fumbled)
	assert_almost_eq(blaster.reload_duration, settings.reload_time + settings.fumble_time, 0.001)
	blaster.reload_elapsed = (
		(settings.sweet_spot_start + settings.sweet_spot_width * 0.5) * (settings.reload_time)
	)
	assert_false(_player.reload(), "one timing press per reload")
	assert_true(blaster.reloading)


func test_reloading_slows_the_player_down() -> void:
	_player.add_cargo(CYAN, 100.0)
	_blaster().rounds = 0
	_player.reload()
	Input.action_press(&"move_left")
	await wait_physics_frames(20)
	var expected: float = _player.settings.move_speed * _player.settings.reload_move_speed
	assert_almost_eq(Vector2(_player.velocity.x, _player.velocity.z).length(), expected, 0.01)


func test_shotgun_loads_one_shell_after_another_and_fires_mid_reload() -> void:
	var shotgun := _equip(SHOTGUN) as RangedWeapon
	shotgun.rounds = 0
	_player.add_cargo(CYAN, 2.5)
	assert_true(_player.reload())
	await _finish_round(shotgun)
	assert_eq(shotgun.rounds, 1)
	assert_true(shotgun.reloading, "goes on with the next shell")
	await _finish_round(shotgun)
	assert_eq(shotgun.rounds, 2)
	assert_false(shotgun.reloading, "the ore pays no third shell")
	assert_almost_eq(_player.cargo[CYAN], 0.5, 0.001)

	_player.add_cargo(CYAN, 10.0)
	_player.reload()
	await _attack_once()
	assert_eq(_fired.size(), shotgun.settings.pellets, "fires the loaded shells")
	assert_eq(shotgun.rounds, 1)
	assert_false(shotgun.reloading, "firing stops the reload")


func test_shotgun_shells_timed_in_a_row_load_quicker() -> void:
	var shotgun := _equip(SHOTGUN) as RangedWeapon
	var settings: RangedWeaponSettings = shotgun.settings
	shotgun.rounds = 0
	_player.add_cargo(CYAN, 100.0)
	_player.reload()
	for shell: int in 2:
		shotgun.reload_elapsed = (
			(settings.sweet_spot_start + settings.sweet_spot_width * 0.5) * shotgun.reload_duration
		)
		assert_true(_player.reload())
	assert_eq(shotgun.rounds, 2)
	assert_eq(shotgun.chain, 2)
	assert_almost_eq(
		shotgun.reload_duration, settings.reload_time * (1.0 - 2.0 * settings.chain_speedup), 0.001
	)
	shotgun.reload_elapsed = 0.0
	_player.reload()
	assert_eq(shotgun.chain, 0, "a miss breaks the chain")


func test_switching_keeps_the_rounds_and_cancels_a_reload() -> void:
	var blaster := _blaster()
	blaster.rounds = 12
	_player.switch_weapon()
	assert_eq(_player.get_weapon_type(), HAMMER)
	_player.switch_weapon()
	blaster = _blaster()
	assert_eq(blaster.rounds, 12)

	_player.add_cargo(CYAN, 100.0)
	_player.reload()
	_player.switch_weapon()
	_player.switch_weapon()
	blaster = _blaster()
	assert_false(blaster.reloading)
	assert_eq(blaster.rounds, 0, "the magazine was thrown away")


func test_reloads_are_free_aboard() -> void:
	var blaster := _blaster()
	blaster.rounds = 0
	_player.ammo_free = true
	await _finish_reload(blaster)
	assert_eq(blaster.rounds, blaster.capacity())


func _blaster() -> RangedWeapon:
	assert_eq(_player.get_weapon_type(), BLASTER)
	return _player.weapon as RangedWeapon


func _ring() -> ReloadRing:
	return _player.get_node("ReloadRing") as ReloadRing


func _equip(weapon_type: WeaponType) -> Weapon:
	_player.loadout.assign(0, weapon_type)
	return _player.weapon


func _finish_reload(weapon: RangedWeapon) -> void:
	if not weapon.reloading:
		assert_true(_player.reload())
	await _finish_round(weapon)


## Skips to the end of the current reload (round).
func _finish_round(weapon: RangedWeapon) -> void:
	weapon.reload_elapsed = weapon.reload_duration
	await wait_physics_frames(1)


func _attack_once() -> void:
	Input.action_press(&"attack")
	await wait_physics_frames(1)
	Input.action_release(&"attack")
	await wait_physics_frames(1)


func _add_player(at: Vector3) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.position = at
	_arena.add_child(player)
	return player


func _add_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.5, 0.0)
	_arena.add_child(body)


func _on_child_entered(node: Node) -> void:
	var projectile := node as Projectile
	if projectile:
		_fired.append(projectile)
