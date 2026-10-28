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


func test_weapons_start_full_and_each_shot_uses_a_round() -> void:
	var harl := _harl()
	assert_eq(harl.capacity(), harl.feed.magazine)
	assert_eq(harl.rounds, harl.capacity())
	await _attack_once()
	assert_eq(_fired.size(), 1)
	assert_eq(harl.rounds, harl.capacity() - 1)


func test_empty_weapon_without_ore_neither_fires_nor_reloads() -> void:
	var harl := _harl()
	harl.rounds = 0
	watch_signals(harl)
	await _attack_once()
	assert_eq(_fired.size(), 0)
	assert_false(harl.reloading)
	assert_signal_emitted(harl, "reload_denied")
	await wait_process_frames(1)
	var color: Color = _ring().shown(&"ammo_color")
	assert_eq(Color(color, 1.0), Color(SuitRing.FUMBLE_COLOR, 1.0), "the ring flashes red")
	assert_false(_player.reload(), "nothing pays a reload")


func test_spare_magazines_show_on_the_ring_and_refill_for_new_runs() -> void:
	_give_spares(2)
	await wait_process_frames(2)
	assert_eq(_number(&"spare_slots"), 2.0)
	assert_eq(_number(&"spare_fill"), 2.0)
	_harl().spare_rounds = 0
	await wait_process_frames(1)
	assert_eq(_number(&"spare_fill"), 0.0)
	assert_gt(_ring().spares_alpha, 0.0, "a used spare shows the ticks")
	_player.switch_weapon()
	await wait_process_frames(1)
	assert_false(_ring().shows_ammo(), "nothing to show with Dray")
	assert_eq(_number(&"spare_alpha"), 0.0)
	_player.switch_weapon()
	assert_eq(_harl().spare_rounds, 0, "kept while holstered")
	_player.refill_ammo()
	assert_eq(_harl().spare_rounds, 2 * _harl().capacity())


func test_new_runs_and_respawns_fill_the_magazines() -> void:
	_harl().rounds = 3
	_player.switch_weapon()
	_player.refill_ammo()
	_player.switch_weapon()
	assert_eq(_harl().rounds, _harl().capacity())
	_harl().rounds = 0
	_player.take_damage(1000.0)
	_player.respawn(Vector3.ZERO)
	assert_eq(_harl().rounds, _harl().capacity())


func test_holding_interact_next_to_a_teammate_hands_them_a_magazine() -> void:
	var teammate: Player = _add_player(Vector3(1.0, 0.0, 0.0))
	await wait_physics_frames(1)
	var their_harl := teammate.get_ammo() as MagazineAmmo
	their_harl.rounds = 3
	_player.cargo.add(KYRITE, 20.0)
	Input.action_press(&"interact")
	await wait_physics_frames(2)
	assert_eq(_player.give_ammo_target, teammate)
	await wait_process_frames(1)
	assert_eq(_number(&"give_alpha"), 1.0, "the ring fills while handing it over")
	await wait_seconds(_player.settings.give_ammo_time + 0.1)
	assert_eq(their_harl.rounds, their_harl.capacity())
	assert_almost_eq(_player.cargo.amount(KYRITE), 20.0 - 6.0, 0.001)
	assert_null(_player.give_ammo_target, "once per hold")


func test_teammates_without_ore_get_nothing() -> void:
	var teammate: Player = _add_player(Vector3(1.0, 0.0, 0.0))
	await wait_physics_frames(1)
	(teammate.get_ammo() as MagazineAmmo).rounds = 3
	assert_false(_player.give_ammo(teammate))
	assert_eq((teammate.get_ammo() as MagazineAmmo).rounds, 3)


func test_ore_value_and_spending() -> void:
	var cargo: Dictionary[OreType, float] = {VYREL: 2.0, KYRITE: 1.0, OLVANE: 4.0}
	assert_almost_eq(OreAmmo.value(cargo), 1.0 + 4.0 * 1.25 + 2.0 * 1.5, 0.001)
	assert_eq(OreAmmo.affordable(cargo, 0.25), 36)
	_player.cargo.add(VYREL, 2.0)
	_player.cargo.add(OLVANE, 4.0)
	_player.cargo.add(KYRITE, 1.0)
	OreAmmo.spend(_player, 3.5)
	assert_almost_eq(_player.cargo.amount(KYRITE), 0.0, 0.001)
	assert_almost_eq(_player.cargo.amount(OLVANE), 2.0, 0.001)
	assert_almost_eq(_player.cargo.amount(VYREL), 2.0, 0.001, "rare ore is spent last")


func test_magazine_upgrade_holds_more_and_lights_its_pips() -> void:
	var pips := _player.weapon.get_node("CapacityPips") as MkPips
	assert_eq(pips.lit_count(), 1)
	_player.upgrades.raise(HARL.get_part(WeaponPart.Stat.CAPACITY))
	assert_eq(_harl().capacity(), roundi(_harl().feed.magazine * 1.5))
	assert_eq(_harl().rounds, _harl().capacity(), "filled to the new size aboard")
	assert_eq(pips.lit_count(), 2)


func test_counter_shows_the_loaded_share_and_warns() -> void:
	var harl := _harl()
	var gauge: AmmoGauge = _player.weapon.get_gauge()
	assert_eq(_lit_segments(gauge, harl), 6)
	@warning_ignore("integer_division")
	harl.rounds = harl.capacity() / 2
	assert_eq(_lit_segments(gauge, harl), 3)
	harl.rounds = 2
	var glow: Array[Color] = gauge.segment_glow(harl, 6)
	assert_true(glow[0] == AmmoGauge.WARNING * gauge.energy or glow[0] == AmmoGauge.DARK)
	harl.rounds = 0
	glow = gauge.segment_glow(harl, 6)
	assert_true(glow[0] == AmmoGauge.EMPTY * gauge.energy * 0.4 or glow[0] == AmmoGauge.DARK)


func test_shell_strip_has_a_shell_per_round() -> void:
	var brask := _equip(BRASK).ammo as MagazineAmmo
	assert_eq(_player.weapon.get_gauge().get_child_count(), brask.capacity())
	_player.upgrades.raise(BRASK.get_part(WeaponPart.Stat.CAPACITY))
	_player.upgrades.raise(BRASK.get_part(WeaponPart.Stat.CAPACITY))
	brask = _player.get_ammo() as MagazineAmmo
	assert_eq(brask.capacity(), brask.feed.magazine * 2)
	assert_eq(_player.weapon.get_gauge().get_child_count(), brask.capacity())


func test_ring_shows_a_reload() -> void:
	_harl().rounds = 0
	_player.cargo.add(KYRITE, 100.0)
	_player.reload()
	await wait_process_frames(2)
	assert_true(_ring().visible)
	assert_eq(_number(&"ammo_alpha"), 1.0)
	var window: Vector2 = _ring().shown(&"ammo_window")
	assert_almost_eq(window.x, _harl().feed.sweet_spot_start, 0.001, "the timing window")
	assert_lt(_number(&"ammo_fill"), 1.0, "fills up during the reload")


func _lit_segments(gauge: AmmoGauge, weapon: MagazineAmmo) -> int:
	var lit: int = 0
	for glow: Color in gauge.segment_glow(weapon, 6):
		if glow != AmmoGauge.DARK:
			lit += 1
	return lit


func _harl() -> MagazineAmmo:
	assert_eq(_player.get_weapon_type(), HARL)
	return _player.get_ammo() as MagazineAmmo


func _ring() -> SuitRing:
	return _player.get_node("SuitRing") as SuitRing


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


func _number(parameter: StringName) -> float:
	var value: float = _ring().shown(parameter)
	return value
