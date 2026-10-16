extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const BLASTER: WeaponType = preload("res://game/weapons/types/blaster.tres")
const SHOTGUN: WeaponType = preload("res://game/weapons/types/shotgun.tres")
const HAMMER: WeaponType = preload("res://game/weapons/types/hammer.tres")
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
	_player.arsenal.unlock(SHOTGUN)
	_fired.clear()
	_arena.child_entered_tree.connect(_on_child_entered)
	await wait_physics_frames(1)


func after_each() -> void:
	for action: StringName in [&"attack", &"interact", &"move_left"]:
		Input.action_release(action)


func test_weapons_start_full_and_each_shot_uses_a_round() -> void:
	var blaster := _blaster()
	assert_eq(blaster.capacity(), blaster.settings.magazine)
	assert_eq(blaster.rounds, blaster.capacity())
	await _attack_once()
	assert_eq(_fired.size(), 1)
	assert_eq(blaster.rounds, blaster.capacity() - 1)


func test_empty_weapon_without_ore_neither_fires_nor_reloads() -> void:
	var blaster := _blaster()
	blaster.rounds = 0
	watch_signals(blaster)
	await _attack_once()
	assert_eq(_fired.size(), 0)
	assert_false(blaster.reloading)
	assert_signal_emitted(blaster, "reload_denied")
	assert_true(_ring().visible, "the ring flashes red")
	assert_false(_player.reload(), "nothing pays a reload")


func test_spare_magazines_show_on_the_belt_and_refill_for_new_runs() -> void:
	_give_spares(2)
	var pouches := _player.get_node("SparePouches") as SparePouches
	await wait_process_frames(1)
	assert_true(pouches.visible)
	assert_eq(pouches.lit_count(), 2)
	_blaster().spare_rounds = 0
	await wait_process_frames(1)
	assert_eq(pouches.lit_count(), 0)
	_player.switch_weapon()
	await wait_process_frames(1)
	assert_false(pouches.visible, "nothing to show with the hammer")
	_player.switch_weapon()
	assert_eq(_blaster().spare_rounds, 0, "kept while holstered")
	_player.refill_ammo()
	assert_eq(_blaster().spare_rounds, 2 * _blaster().capacity())


func test_new_runs_and_respawns_fill_the_magazines() -> void:
	_blaster().rounds = 3
	_player.switch_weapon()
	_player.refill_ammo()
	_player.switch_weapon()
	assert_eq(_blaster().rounds, _blaster().capacity())
	_blaster().rounds = 0
	_player.take_damage(1000.0)
	_player.respawn(Vector3.ZERO)
	assert_eq(_blaster().rounds, _blaster().capacity())


func test_holding_interact_next_to_a_teammate_hands_them_a_magazine() -> void:
	var teammate: Player = _add_player(Vector3(1.0, 0.0, 0.0))
	await wait_physics_frames(1)
	var their_blaster := teammate.weapon as RangedWeapon
	their_blaster.rounds = 3
	_player.add_cargo(KYRITE, 20.0)
	Input.action_press(&"interact")
	await wait_physics_frames(2)
	assert_eq(_player.give_ammo_target, teammate)
	assert_true(_ring().visible, "the ring fills while handing it over")
	await wait_seconds(_player.settings.give_ammo_time + 0.1)
	assert_eq(their_blaster.rounds, their_blaster.capacity())
	assert_almost_eq(_player.cargo[KYRITE], 20.0 - 6.0, 0.001)
	assert_null(_player.give_ammo_target, "once per hold")


func test_teammates_without_ore_get_nothing() -> void:
	var teammate: Player = _add_player(Vector3(1.0, 0.0, 0.0))
	await wait_physics_frames(1)
	(teammate.weapon as RangedWeapon).rounds = 3
	assert_false(_player.give_ammo(teammate))
	assert_eq((teammate.weapon as RangedWeapon).rounds, 3)


func test_ore_value_and_spending() -> void:
	var cargo: Dictionary[OreType, float] = {VYREL: 2.0, KYRITE: 1.0, OLVANE: 4.0}
	assert_almost_eq(OreAmmo.value(cargo), 1.0 + 4.0 * 1.25 + 2.0 * 1.5, 0.001)
	assert_eq(OreAmmo.affordable(cargo, 0.25), 36)
	_player.add_cargo(VYREL, 2.0)
	_player.add_cargo(OLVANE, 4.0)
	_player.add_cargo(KYRITE, 1.0)
	OreAmmo.spend(_player, 3.5)
	assert_almost_eq(_player.cargo[KYRITE], 0.0, 0.001)
	assert_almost_eq(_player.cargo[OLVANE], 2.0, 0.001)
	assert_almost_eq(_player.cargo[VYREL], 2.0, 0.001, "rare ore is spent last")


func test_magazine_upgrade_holds_more_and_lights_its_pips() -> void:
	var pips := _blaster().get_node("MagazinePips") as MkPips
	assert_eq(pips.lit_count(), 1)
	_player.upgrades.raise(BLASTER.magazine_upgrade)
	assert_eq(_blaster().capacity(), roundi(_blaster().settings.magazine * 1.5))
	assert_eq(_blaster().rounds, _blaster().capacity(), "filled to the new size aboard")
	assert_eq(pips.lit_count(), 2)


func test_counter_shows_the_loaded_share_and_warns() -> void:
	var blaster := _blaster()
	var gauge := blaster.get_node("AmmoGauge") as AmmoGauge
	assert_eq(_lit_segments(gauge, blaster), 6)
	blaster.rounds = blaster.capacity() / 2
	assert_eq(_lit_segments(gauge, blaster), 3)
	blaster.rounds = 2
	var glow: Array[Color] = gauge.segment_glow(blaster, 6)
	assert_true(glow[0] == AmmoGauge.WARNING * gauge.energy or glow[0] == AmmoGauge.DARK)
	blaster.rounds = 0
	glow = gauge.segment_glow(blaster, 6)
	assert_true(glow[0] == AmmoGauge.EMPTY * gauge.energy * 0.4 or glow[0] == AmmoGauge.DARK)


func test_shell_strip_has_a_shell_per_round() -> void:
	var shotgun := _equip(SHOTGUN) as RangedWeapon
	assert_eq(shotgun.get_node("AmmoGauge").get_child_count(), shotgun.capacity())
	_player.upgrades.raise(SHOTGUN.magazine_upgrade)
	_player.upgrades.raise(SHOTGUN.magazine_upgrade)
	shotgun = _player.weapon as RangedWeapon
	assert_eq(shotgun.capacity(), shotgun.settings.magazine * 2)
	assert_eq(shotgun.get_node("AmmoGauge").get_child_count(), shotgun.capacity())


func test_ring_shows_a_reload() -> void:
	_blaster().rounds = 0
	_player.add_cargo(KYRITE, 100.0)
	_player.reload()
	await wait_process_frames(2)
	assert_true(_ring().visible)


func _lit_segments(gauge: AmmoGauge, weapon: RangedWeapon) -> int:
	var lit: int = 0
	for glow: Color in gauge.segment_glow(weapon, 6):
		if glow != AmmoGauge.DARK:
			lit += 1
	return lit


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
