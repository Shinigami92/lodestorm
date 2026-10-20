extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")

var _arena: Node3D
var _player: Player
var _fired: Array[Projectile] = []


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_add_floor()
	_player = _add_player(Vector3.ZERO)
	_player.arsenal.unlock(BRASK)
	_fired.clear()
	_arena.child_entered_tree.connect(_on_child_entered)
	await wait_physics_frames(1)


func after_each() -> void:
	for action: StringName in [&"attack", &"interact", &"move_left"]:
		Input.action_release(action)


func test_magazine_reload_throws_away_the_rest_and_pays_the_commonest_ore_first() -> void:
	var harl := _harl()
	harl.rounds = 20
	_player.add_cargo(OLVANE, 10.0)
	_player.add_cargo(KYRITE, 5.0)
	assert_true(_player.reload())
	assert_true(harl.reloading)
	assert_eq(harl.rounds, 0, "the rounds left in the magazine are lost")
	await _finish_reload(harl)
	assert_false(harl.reloading)
	assert_eq(harl.rounds, harl.capacity())
	# A full magazine costs 24 * 0.25 = 6: all 5 kyrite, then 1 / 1.25 = 0.8 olvane.
	assert_almost_eq(_player.cargo[KYRITE], 0.0, 0.001)
	assert_almost_eq(_player.cargo[OLVANE], 9.2, 0.001)


func test_full_magazine_ignores_reload_without_a_warning() -> void:
	var harl := _harl()
	watch_signals(harl)
	assert_false(_player.reload())
	assert_signal_not_emitted(harl, "reload_denied")
	assert_false(harl.reloading)


func test_magazine_reload_loads_what_the_ore_pays() -> void:
	var harl := _harl()
	harl.rounds = 10
	_player.add_cargo(KYRITE, 2.0)
	assert_false(_player.reload(), "8 rounds wouldn't be more than the 10 loaded")
	assert_eq(harl.rounds, 10)
	harl.rounds = 0
	await _finish_reload(harl)
	assert_eq(harl.rounds, 8)
	assert_almost_eq(_player.cargo[KYRITE], 0.0, 0.001)


func test_empty_weapon_reloads_by_itself() -> void:
	var harl := _harl()
	harl.rounds = 1
	_player.add_cargo(KYRITE, 100.0)
	await _attack_once()
	assert_eq(harl.rounds, 0)
	assert_true(harl.reloading, "the last shot starts a reload")


func test_timing_press_within_the_window_finishes_the_reload() -> void:
	var harl := _harl()
	harl.rounds = 0
	_player.add_cargo(KYRITE, 100.0)
	assert_true(_player.reload())
	var feed: MagazineFeed = harl.feed
	harl.reload_elapsed = (
		(feed.sweet_spot_start + feed.sweet_spot_width * 0.5) * (feed.reload_time)
	)
	watch_signals(harl)
	assert_true(_player.reload())
	assert_signal_emitted_with_parameters(harl, "reload_timed", [true])
	assert_false(harl.reloading)
	assert_eq(harl.rounds, harl.capacity())


func test_timing_press_outside_the_window_takes_longer() -> void:
	var harl := _harl()
	harl.rounds = 0
	_player.add_cargo(KYRITE, 100.0)
	_player.reload()
	var feed: MagazineFeed = harl.feed
	harl.reload_elapsed = feed.sweet_spot_start * 0.5 * feed.reload_time
	watch_signals(harl)
	assert_true(_player.reload())
	assert_signal_emitted_with_parameters(harl, "reload_timed", [false])
	assert_true(harl.fumbled)
	assert_almost_eq(harl.reload_duration, feed.reload_time + feed.fumble_time, 0.001)
	harl.reload_elapsed = (
		(feed.sweet_spot_start + feed.sweet_spot_width * 0.5) * (feed.reload_time)
	)
	assert_false(_player.reload(), "one timing press per reload")
	assert_true(harl.reloading)


func test_reloading_slows_the_player_down() -> void:
	_player.add_cargo(KYRITE, 100.0)
	_harl().rounds = 0
	_player.reload()
	Input.action_press(&"move_left")
	await wait_physics_frames(20)
	var expected: float = _player.settings.move_speed * _player.settings.reload_move_speed
	assert_almost_eq(Vector2(_player.velocity.x, _player.velocity.z).length(), expected, 0.01)


func test_brask_loads_one_shell_after_another_and_fires_mid_reload() -> void:
	var brask := _equip(BRASK).ammo as MagazineAmmo
	brask.rounds = 0
	_player.add_cargo(KYRITE, 2.5)
	assert_true(_player.reload())
	await _finish_round(brask)
	assert_eq(brask.rounds, 1)
	assert_true(brask.reloading, "goes on with the next shell")
	await _finish_round(brask)
	assert_eq(brask.rounds, 2)
	assert_false(brask.reloading, "the ore pays no third shell")
	assert_almost_eq(_player.cargo[KYRITE], 0.5, 0.001)

	_player.add_cargo(KYRITE, 10.0)
	_player.reload()
	await _attack_once()
	assert_eq(
		_fired.size(), (BRASK.delivery as ProjectileDelivery).pellets, "fires the loaded shells"
	)
	assert_eq(brask.rounds, 1)
	assert_false(brask.reloading, "firing stops the reload")


func test_brask_shells_timed_in_a_row_load_quicker() -> void:
	var brask := _equip(BRASK).ammo as MagazineAmmo
	var feed: MagazineFeed = brask.feed
	brask.rounds = 0
	_player.add_cargo(KYRITE, 100.0)
	_player.reload()
	for shell: int in 2:
		brask.reload_elapsed = (
			(feed.sweet_spot_start + feed.sweet_spot_width * 0.5) * brask.reload_duration
		)
		assert_true(_player.reload())
	assert_eq(brask.rounds, 2)
	assert_eq(brask.chain, 2)
	assert_almost_eq(
		brask.reload_duration, feed.reload_time * (1.0 - 2.0 * feed.chain_speedup), 0.001
	)
	brask.reload_elapsed = 0.0
	_player.reload()
	assert_eq(brask.chain, 0, "a miss breaks the chain")


func test_switching_keeps_the_rounds_and_cancels_a_reload() -> void:
	var harl := _harl()
	harl.rounds = 12
	_player.switch_weapon()
	assert_eq(_player.get_weapon_type(), DRAY)
	_player.switch_weapon()
	harl = _harl()
	assert_eq(harl.rounds, 12)

	_player.add_cargo(KYRITE, 100.0)
	_player.reload()
	_player.switch_weapon()
	_player.switch_weapon()
	harl = _harl()
	assert_false(harl.reloading)
	assert_eq(harl.rounds, 0, "the magazine was thrown away")


func test_reloads_use_the_spare_magazines_before_ore() -> void:
	_give_spares(2)
	var harl := _harl()
	assert_eq(harl.spare_rounds, 2 * harl.capacity())
	_player.add_cargo(KYRITE, 100.0)
	for spare: int in 2:
		harl.rounds = 5
		await _finish_reload(harl)
		assert_eq(harl.rounds, harl.capacity(), "the rest is thrown away, a full one goes in")
		assert_eq(harl.spare_rounds, (1 - spare) * harl.capacity())
		assert_eq(_player.cargo[KYRITE], 100.0, "spares cost no ore")
	harl.rounds = 0
	await _finish_reload(harl)
	assert_eq(harl.rounds, harl.capacity())
	assert_lt(_player.cargo[KYRITE], 100.0, "then ore pays")


func test_empty_weapon_with_spares_reloads_without_ore() -> void:
	_give_spares(1)
	var harl := _harl()
	harl.rounds = 1
	await _attack_once()
	assert_true(harl.reloading)
	await _finish_round(harl)
	assert_eq(harl.rounds, harl.capacity())
	assert_eq(harl.spare_rounds, 0)


func test_brask_takes_spare_shells_one_by_one() -> void:
	_give_spares(1)
	var brask := _equip(BRASK).ammo as MagazineAmmo
	assert_eq(brask.spare_rounds, brask.capacity())
	brask.rounds = brask.capacity() - 2
	await _finish_reload(brask)
	assert_eq(brask.spare_rounds, brask.capacity() - 1)
	await _finish_round(brask)
	assert_eq(brask.rounds, brask.capacity())
	assert_eq(brask.spare_rounds, brask.capacity() - 2)
	assert_false(brask.reloading)


func test_reloads_are_free_aboard() -> void:
	var harl := _harl()
	harl.rounds = 0
	_player.ammo_free = true
	await _finish_reload(harl)
	assert_eq(harl.rounds, harl.capacity())


func _harl() -> MagazineAmmo:
	assert_eq(_player.get_weapon_type(), HARL)
	return _player.get_ammo() as MagazineAmmo


func _equip(weapon_type: WeaponType) -> Weapon:
	_player.loadout.assign(0, weapon_type)
	return _player.weapon


func _finish_reload(weapon: MagazineAmmo) -> void:
	if not weapon.reloading:
		assert_true(_player.reload())
	await _finish_round(weapon)


## Skips to the end of the current reload (round).
func _finish_round(weapon: MagazineAmmo) -> void:
	weapon.reload_elapsed = weapon.reload_duration
	await wait_physics_frames(1)


func _attack_once() -> void:
	Input.action_press(&"attack")
	await wait_physics_frames(1)
	Input.action_release(&"attack")
	await wait_physics_frames(1)


## A player without spare magazines, so reloads pay ore (`_give_spares` adds them).
func _add_player(at: Vector3) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.settings = player.settings.duplicate() as PlayerSettings
	player.settings.spare_magazines = 0
	player.position = at
	_arena.add_child(player)
	return player


func _give_spares(magazines: int) -> void:
	_player.settings.spare_magazines = magazines
	_player.refill_ammo()


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
