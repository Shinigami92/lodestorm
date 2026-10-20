extends GutTest
## Scald (a cone of flame setting aliens burning), Kith (a beam healing teammates and repairing
## miners) and Zenith (a piercing beam hitting harder the longer it stays), and the heat they share.

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const MINER_SCENE: PackedScene = preload("res://game/mining/miner.tscn")
const SCALD: WeaponType = preload("res://game/weapons/types/scald/scald.tres")
const KITH: WeaponType = preload("res://game/weapons/types/kith/kith.tres")
const ZENITH: WeaponType = preload("res://game/weapons/types/zenith/zenith.tres")
const CONE: ConeDelivery = preload("res://game/weapons/types/scald/delivery.tres")
const SCALD_DAMAGE: DamageEffect = preload("res://game/weapons/types/scald/damage.tres")
const BURN: BurnEffect = preload("res://game/weapons/types/scald/burn.tres")
const HEAT: HeatFeed = preload("res://game/weapons/types/scald/feed.tres")
const KITH_HEAL: HealEffect = preload("res://game/weapons/types/kith/heal.tres")
const ZENITH_BEAM: BeamDelivery = preload("res://game/weapons/types/zenith/delivery.tres")

var _arena: Node3D
var _player: Player


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0))
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	for weapon_type: WeaponType in [SCALD, KITH, ZENITH]:
		_player.arsenal.unlock(weapon_type)
	await wait_physics_frames(1)


func after_each() -> void:
	Input.action_release(&"attack")


func test_heat_builds_while_firing_and_cools_after() -> void:
	var scald: Weapon = await _drawn(SCALD)
	var ammo := scald.ammo as HeatAmmo
	await _hold(0.5)
	var heat: float = ammo.heat
	assert_almost_eq(heat, HEAT.heat_per_round * SCALD.attack_rate * 0.5, 0.03)
	assert_lt(ammo.rounds, ammo.capacity(), "it burns fuel")
	await wait_seconds(HEAT.cool_delay * 0.5)
	assert_eq(ammo.heat, heat, "not before the delay")
	await wait_seconds(HEAT.cool_delay)
	assert_lt(ammo.heat, heat, "cooling by itself")


func test_full_heat_overheats_and_vents_before_it_fires_again() -> void:
	var scald: Weapon = await _drawn(SCALD)
	var ammo := scald.ammo as HeatAmmo
	ammo.heat = 1.0 - HEAT.heat_per_round * 0.5
	await _hold(0.05)
	assert_true(ammo.venting, "overheated")
	assert_true(ammo.refilling(), "the ring and gauge show it like a reload")
	assert_false(ammo.can_attack())
	var rounds: int = ammo.rounds
	await _hold(HEAT.vent_time * 0.5)
	assert_eq(ammo.rounds, rounds, "no fire while it vents")
	await wait_seconds(HEAT.vent_time * 0.5 + 0.1)
	assert_false(ammo.venting)
	assert_eq(ammo.heat, 0.0)


func test_a_timed_press_vents_at_once_and_a_miss_takes_longer() -> void:
	var scald: Weapon = await _drawn(SCALD)
	var ammo := scald.ammo as HeatAmmo
	ammo.heat = 1.0
	assert_true(ammo.reload(), "reload while hot vents")
	assert_true(ammo.venting)
	await wait_seconds(HEAT.vent_time * (HEAT.sweet_spot_start + HEAT.sweet_spot_width * 0.5))
	assert_true(ammo.reload(), "the timing press")
	assert_false(ammo.venting, "within the window: cool at once")
	assert_eq(ammo.heat, 0.0)
	ammo.heat = 1.0
	ammo.reload()
	await wait_seconds(0.1)
	ammo.reload()
	assert_true(ammo.fumbled)
	await wait_seconds(HEAT.vent_time)
	assert_true(ammo.venting, "a miss takes longer")
	await wait_seconds(HEAT.fumble_time)
	assert_false(ammo.venting)


func test_reload_swaps_the_cell_when_it_is_cool() -> void:
	var scald: Weapon = await _drawn(SCALD)
	var ammo := scald.ammo as HeatAmmo
	ammo.rounds = 10
	ammo.heat = HEAT.vent_from * 0.5
	assert_true(ammo.reload())
	assert_false(ammo.venting)
	assert_true(ammo.reloading, "a new cell")


func test_scald_fills_its_cone_and_sets_aliens_burning() -> void:
	await _drawn(SCALD)
	var inside := _add_alien(Vector3(0.0, 0.0, -3.0), 1000.0)
	var aside := _add_alien(Vector3(3.0, 0.0, -1.5), 1000.0)
	var beyond := _add_alien(Vector3(0.0, 0.0, -CONE.reach - 2.0), 1000.0)
	var sheltered := _add_alien(Vector3(-1.2, 0.0, -4.0), 1000.0)
	_add_box(Vector3(-0.7, 1.5, -3.0), Vector3(0.6, 3.0, 0.3))
	await wait_physics_frames(1)
	_player.weapon.aim_target = null
	await _hold(0.5)
	assert_gt(_dealt(inside), SCALD_DAMAGE.damage, "in the cone")
	assert_eq(_dealt(aside), 0.0, "outside its angle")
	assert_eq(_dealt(beyond), 0.0, "beyond its reach")
	assert_eq(_dealt(sheltered), 0.0, "behind rock")
	assert_true(Burning.is_burning(inside))
	var dealt: float = _dealt(inside)
	await wait_seconds(BURN.seconds * 0.5)
	assert_gt(_dealt(inside), dealt, "it burns on")
	await wait_seconds(BURN.seconds)
	assert_false(Burning.is_burning(inside), "burned out")
	assert_almost_eq(
		_dealt(inside) - dealt, BURN.damage_per_second * BURN.seconds, BURN.damage_per_second
	)


func test_burning_a_second_time_refreshes_it_without_adding_up() -> void:
	var alien := _add_alien(Vector3(0.0, 0.0, -20.0), 1000.0)
	await wait_physics_frames(1)
	Burning.ignite(alien, 10.0, 2.0, null)
	Burning.ignite(alien, 4.0, 3.0, null)
	var burning := alien.get_node(NodePath(Burning.NODE_NAME)) as Burning
	assert_eq(burning.damage_per_second, 10.0, "the stronger")
	assert_eq(burning.time_left, 3.0, "the longer")
	assert_eq(alien.get_children().filter(func(n: Node) -> bool: return n is Burning).size(), 1)


func test_kith_heals_the_first_teammate_and_repairs_a_miner() -> void:
	await _drawn(KITH)
	var teammate := PLAYER_SCENE.instantiate() as Player
	teammate.local = false
	teammate.position = Vector3(0.0, 0.0, -5.0)
	_arena.add_child(teammate)
	var miner := _add_miner(Vector3(0.0, 0.0, -9.0))
	await wait_physics_frames(1)
	teammate.take_damage(50.0)
	miner.take_damage(50.0)
	var hurt: float = teammate.health
	var damaged: float = miner.health
	await _hold(0.5)
	assert_gt(teammate.health, hurt, "healed")
	assert_almost_eq(
		teammate.health - hurt, KITH_HEAL.heal * KITH.attack_rate * 0.5, KITH_HEAL.heal * 2.0
	)
	assert_eq(miner.health, damaged, "the beam stops at the teammate")
	teammate.free()
	await _hold(0.5)
	assert_gt(miner.health, damaged, "repaired")


func test_kith_stings_aliens() -> void:
	await _drawn(KITH)
	var alien := _add_alien(Vector3(0.0, 0.0, -6.0), 1000.0)
	await _hold(0.5)
	assert_gt(_dealt(alien), 0.0)
	assert_lt(_dealt(alien), 20.0, "weakly")


func test_zenith_pierces_aliens_and_passes_players_but_not_rock() -> void:
	await _drawn(ZENITH)
	var teammate := PLAYER_SCENE.instantiate() as Player
	teammate.local = false
	teammate.position = Vector3(0.0, 0.0, -3.0)
	_arena.add_child(teammate)
	var first := _add_alien(Vector3(0.0, 0.0, -6.0), 10000.0)
	var second := _add_alien(Vector3(0.0, 0.0, -10.0), 10000.0)
	var behind := _add_alien(Vector3(0.0, 0.0, -16.0), 10000.0)
	_add_box(Vector3(0.0, 1.5, -13.0), Vector3(3.0, 3.0, 0.5))
	await wait_physics_frames(1)
	var health: float = teammate.health
	await _hold(0.5)
	assert_gt(_dealt(first), 0.0)
	assert_gt(_dealt(second), 0.0, "through the first")
	assert_eq(_dealt(behind), 0.0, "rock stops it")
	assert_eq(teammate.health, health, "no friendly fire")


func test_zenith_hits_harder_the_longer_it_stays() -> void:
	await _drawn(ZENITH)
	var alien := _add_alien(Vector3(0.0, 0.0, -8.0), 100000.0)
	await wait_physics_frames(1)
	await _hold(0.5)
	var early: float = _dealt(alien)
	await _hold(ZENITH_BEAM.ramp_time)
	var before: float = _dealt(alien)
	await _hold(0.5)
	var late: float = _dealt(alien) - before
	# The first half second averages about 1.25 times, the last one the full ramp.
	assert_gt(late, early * ZENITH_BEAM.ramp * 0.6, "ramped up")


func _drawn(weapon_type: WeaponType) -> Weapon:
	_player.loadout.assign(0, weapon_type)
	assert_eq(_player.get_weapon_type(), weapon_type)
	await wait_seconds(weapon_type.draw_time + 0.05)
	return _player.weapon


func _hold(seconds: float) -> void:
	Input.action_press(&"attack")
	await wait_seconds(seconds)
	Input.action_release(&"attack")
	await wait_physics_frames(1)


func _dealt(alien: Alien) -> float:
	return alien.max_health() - alien.health


## An alien standing still (it notices nobody) with `health`.
func _add_alien(at: Vector3, health: float) -> Alien:
	var alien := SWARMER.spawn()
	alien.strain = alien.strain.duplicate() as AlienStrain
	alien.strain.max_health = health
	alien.strain.detection_range = 0.0
	alien.position = at
	_arena.add_child(alien)
	return alien


## A miner of its own (no ore, no hose, no repair by standing next to it) at `at`.
func _add_miner(at: Vector3) -> Miner:
	var miner := MINER_SCENE.instantiate() as Miner
	miner.settings = miner.settings.duplicate() as MinerSettings
	miner.settings.hose_range = 0.0
	miner.settings.repair_range = 0.0
	miner.position = at
	_arena.add_child(miner)
	return miner


func _add_box(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	_arena.add_child(body)
