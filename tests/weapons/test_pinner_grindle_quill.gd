extends GutTest
## Pinner (one shot per press from a battery), Grindle (barrels spinning up) and Quill (a charge
## let go, a full one piercing).

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const PINNER: WeaponType = preload("res://game/weapons/types/pinner/pinner.tres")
const GRINDLE: WeaponType = preload("res://game/weapons/types/grindle/grindle.tres")
const QUILL: WeaponType = preload("res://game/weapons/types/quill/quill.tres")
const BATTERY: BatteryFeed = preload("res://game/weapons/types/pinner/feed.tres")
const SPIN: SpinTrigger = preload("res://game/weapons/types/grindle/trigger.tres")
const CHARGE: ChargeTrigger = preload("res://game/weapons/types/quill/trigger.tres")
const QUILL_DAMAGE: DamageEffect = preload("res://game/weapons/types/quill/damage.tres")

var _arena: Node3D
var _player: Player
var _fired: Array[Projectile] = []


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0))
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	for weapon_type: WeaponType in [PINNER, GRINDLE, QUILL]:
		_player.arsenal.unlock(weapon_type)
	_fired.clear()
	_arena.child_entered_tree.connect(
		func(node: Node) -> void:
			if node is Projectile:
				_fired.append(node as Projectile)
	)
	await wait_physics_frames(1)


func after_each() -> void:
	Input.action_release(&"attack")


func test_pinner_fires_once_per_press() -> void:
	_equip(PINNER)
	Input.action_press(&"attack")
	await wait_seconds(0.5)
	assert_eq(_fired.size(), 1, "holding fires no more")
	Input.action_release(&"attack")
	await wait_physics_frames(1)
	await _attack_once()
	assert_eq(_fired.size(), 2)


func test_pinner_battery_drains_and_recharges_by_itself_for_no_ore() -> void:
	var pinner: Weapon = _equip(PINNER)
	var battery := pinner.ammo as BatteryAmmo
	assert_eq(battery.rounds, BATTERY.cells, "starts full")
	assert_false(battery.uses_spares())
	assert_false(_player.reload(), "nothing to reload by hand")
	for shot: int in BATTERY.cells:
		await _attack_once()
		await wait_seconds(1.0 / PINNER.attack_rate)
	assert_eq(_fired.size(), BATTERY.cells)
	assert_eq(battery.rounds, 0)
	assert_true(battery.refilling(), "drained")
	await _attack_once()
	assert_eq(_fired.size(), BATTERY.cells, "no shot while drained")
	await wait_seconds(BATTERY.drained_recharge_time * 0.5)
	assert_true(battery.refilling())
	assert_almost_eq(battery.refill_share(), 0.5, 0.1)
	await wait_seconds(BATTERY.drained_recharge_time * 0.5 + 0.1)
	assert_false(battery.refilling())
	assert_eq(battery.rounds, BATTERY.cells, "full again")
	assert_true(_player.cargo.is_empty(), "no ore used")


func test_pinner_recharges_after_a_pause_in_firing() -> void:
	var battery := _equip(PINNER).ammo as BatteryAmmo
	for shot: int in 4:
		await _attack_once()
		await wait_seconds(1.0 / PINNER.attack_rate)
	var left: int = battery.rounds
	assert_eq(left, BATTERY.cells - 4)
	await wait_seconds(BATTERY.recharge_delay * 0.5)
	assert_eq(battery.rounds, left, "not yet")
	await wait_seconds(BATTERY.recharge_delay * 0.5 + 2.0 / BATTERY.recharge_rate + 0.05)
	assert_gt(battery.rounds, left)


func test_pinner_recharge_part_recharges_faster() -> void:
	var part: WeaponPart = PINNER.get_part(WeaponPart.Stat.RECHARGE)
	assert_not_null(part)
	for level: int in 7:
		_player.upgrades.raise(part)
	var battery := _equip(PINNER).ammo as BatteryAmmo
	for shot: int in BATTERY.cells:
		await _attack_once()
		await wait_seconds(1.0 / PINNER.attack_rate)
	assert_true(battery.refilling())
	await wait_seconds(BATTERY.drained_recharge_time / part.multiplier(8) + 0.1)
	assert_false(battery.refilling(), "MK8 recharges twice as fast")


func test_grindle_spins_up_before_it_fires() -> void:
	var grindle: Weapon = _equip(GRINDLE)
	Input.action_press(&"attack")
	await wait_seconds(SPIN.spin_up * 0.8)
	assert_eq(_fired.size(), 0, "still spinning up")
	assert_gt(grindle.wind, 0.5)
	assert_lt(grindle.move_share(), 1.0, "slower while spinning")
	await wait_seconds(SPIN.spin_up * 0.2 + 1.0)
	var shots: int = _fired.size()
	assert_between(float(shots), GRINDLE.attack_rate - 2.0, GRINDLE.attack_rate + 1.0)
	assert_almost_eq(grindle.move_share(), SPIN.spinning_move_share, 0.01)
	assert_eq(grindle.ammo.rounds, grindle.ammo.capacity() - shots)


func test_grindle_keeps_spinning_for_a_moment_after_letting_go() -> void:
	var grindle: Weapon = _equip(GRINDLE)
	Input.action_press(&"attack")
	await wait_seconds(SPIN.spin_up + 0.1)
	Input.action_release(&"attack")
	await wait_seconds(SPIN.keep_spinning * 0.5)
	var shots: int = _fired.size()
	await _attack_once()
	assert_eq(_fired.size(), shots + 1, "fires at once")
	await wait_seconds(SPIN.keep_spinning + SPIN.spin_down + 0.1)
	assert_eq(grindle.wind, 0.0, "stopped")
	assert_eq(grindle.move_share(), 1.0)


func test_grindle_spin_part_spins_up_faster() -> void:
	var part: WeaponPart = GRINDLE.get_part(WeaponPart.Stat.SPIN)
	for level: int in 7:
		_player.upgrades.raise(part)
	_equip(GRINDLE)
	Input.action_press(&"attack")
	await wait_seconds(SPIN.spin_up / part.multiplier(8) + 0.1)
	assert_gt(_fired.size(), 0, "MK8 spins up twice as fast")


func test_quill_fires_when_let_go_weaker_without_a_full_charge() -> void:
	var quill: Weapon = _equip(QUILL)
	var near := _add_alien(Vector3(0.0, 0.0, -4.0), 1000.0)
	var far := _add_alien(Vector3(0.0, 0.0, -7.0), 1000.0)
	Input.action_press(&"attack")
	await wait_seconds(CHARGE.charge_time * 0.5)
	assert_eq(_fired.size(), 0, "nothing while charging")
	assert_almost_eq(quill.charge(), 0.5, 0.05)
	var power: float = lerpf(CHARGE.min_power, 1.0, quill.charge())
	Input.action_release(&"attack")
	await wait_physics_frames(1)
	assert_eq(_fired.size(), 1)
	assert_eq(quill.charge(), 0.0)
	await wait_seconds(0.3)
	var dealt: float = near.max_health() - near.health
	assert_almost_eq(dealt, QUILL_DAMAGE.damage * power, QUILL_DAMAGE.damage * 0.05)
	assert_eq(far.health, far.max_health(), "a partial charge stops at the first alien")


func test_quill_full_charge_pierces_every_alien_in_its_line() -> void:
	_equip(QUILL)
	var aliens: Array[Alien] = []
	for z: float in [-4.0, -7.0, -10.0]:
		aliens.append(_add_alien(Vector3(0.0, 0.0, z), 1000.0))
	Input.action_press(&"attack")
	await wait_seconds(CHARGE.charge_time + 0.1)
	Input.action_release(&"attack")
	await wait_seconds(0.4)
	assert_eq(_fired.size(), 1)
	for alien: Alien in aliens:
		assert_almost_eq(alien.max_health() - alien.health, QUILL_DAMAGE.damage, 0.01)


func test_quill_shows_its_line_and_charge_while_charging() -> void:
	var quill: Weapon = _equip(QUILL)
	var line := quill.get_node("SightLine") as SightLine
	var ring := _player.get_node("SuitRing") as SuitRing
	await wait_process_frames(1)
	assert_false(line.visible)
	Input.action_press(&"attack")
	await wait_seconds(CHARGE.charge_time * 0.5)
	assert_true(line.visible)
	var fill: float = ring.shown(&"ammo_fill")
	assert_almost_eq(fill, quill.charge(), 0.1)
	await wait_seconds(CHARGE.charge_time * 0.5 + 0.1)
	var full: Color = ring.shown(&"ammo_color")
	assert_eq(Color(full, 1.0), Color(AmmoGauge.TIMING, 1.0), "white when full")
	Input.action_release(&"attack")
	await wait_physics_frames(2)
	await wait_process_frames(1)
	assert_false(line.visible)


func test_switching_away_loses_a_charge() -> void:
	_player.loadout.assign(1, PINNER)
	var quill: Weapon = _equip(QUILL)
	Input.action_press(&"attack")
	await wait_seconds(CHARGE.charge_time * 0.5)
	assert_gt(quill.charge(), 0.0)
	Input.action_release(&"attack")
	_player.switch_weapon()
	await wait_physics_frames(2)
	assert_eq(_fired.size(), 0, "no shot")


func _equip(weapon_type: WeaponType) -> Weapon:
	_player.loadout.assign(0, weapon_type)
	assert_eq(_player.get_weapon_type(), weapon_type)
	return _player.weapon


func _attack_once() -> void:
	Input.action_press(&"attack")
	await wait_physics_frames(1)
	Input.action_release(&"attack")
	await wait_physics_frames(1)


## An alien standing still (it notices nobody) with `health`.
func _add_alien(at: Vector3, health: float) -> Alien:
	var alien := SWARMER.spawn()
	alien.strain = alien.strain.duplicate() as AlienStrain
	alien.strain.max_health = health
	alien.strain.detection_range = 0.0
	alien.position = at
	_arena.add_child(alien)
	return alien


func _add_box(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	_arena.add_child(body)
