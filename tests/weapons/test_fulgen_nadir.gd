extends GutTest
## Fulgen (lightning to the nearest alien, jumping on) and Nadir (a gravity well pulling aliens in,
## holding them and bursting).

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const DARTER: AlienStrain = preload("res://game/aliens/strains/darter/darter.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const FULGEN: WeaponType = preload("res://game/weapons/types/fulgen/fulgen.tres")
const NADIR: WeaponType = preload("res://game/weapons/types/nadir/nadir.tres")
const CHAIN: ChainDelivery = preload("res://game/weapons/types/fulgen/delivery.tres")
const FULGEN_DAMAGE: DamageEffect = preload("res://game/weapons/types/fulgen/damage.tres")
const WELL: WellDelivery = preload("res://game/weapons/types/nadir/delivery.tres")
const NADIR_DAMAGE: DamageEffect = preload("res://game/weapons/types/nadir/damage.tres")
const BATTERY: BatteryFeed = preload("res://game/weapons/types/nadir/feed.tres")

var _arena: Node3D
var _player: Player


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0))
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	for weapon_type: WeaponType in [FULGEN, NADIR]:
		_player.arsenal.unlock(weapon_type)
	await wait_physics_frames(1)


func after_each() -> void:
	Input.action_release(&"attack")


func test_fulgen_arcs_to_the_nearest_alien_in_its_cone_and_jumps_on() -> void:
	await _drawn(FULGEN)
	var first := _add_alien(Vector3(0.0, 0.0, -6.0))
	var second := _add_alien(Vector3(3.0, 0.0, -8.0))
	var third := _add_alien(Vector3(6.0, 0.0, -10.0))
	var aside := _add_alien(Vector3(9.0, 0.0, 2.0))
	await wait_physics_frames(1)
	await _attack_once()
	var full: float = FULGEN_DAMAGE.damage
	assert_almost_eq(_dealt(first), full, 0.01, "the nearest in the cone")
	assert_almost_eq(_dealt(second), full * CHAIN.jump_share, 0.01, "jumped on")
	assert_almost_eq(_dealt(third), full * CHAIN.jump_share * CHAIN.jump_share, 0.01)
	assert_eq(_dealt(aside), 0.0, "too far from the others and outside the cone")
	assert_eq(_player.arms.weapon.ammo.rounds, _player.arms.weapon.ammo.capacity() - 1)


func test_fulgen_jumps_at_most_its_jumps() -> void:
	await _drawn(FULGEN)
	var line: Array[Alien] = []
	for i: int in CHAIN.jumps + 3:
		line.append(_add_alien(Vector3(3.0 * i, 0.0, -6.0)))
	await wait_physics_frames(1)
	await _attack_once()
	for i: int in line.size():
		if i <= CHAIN.jumps:
			assert_gt(_dealt(line[i]), 0.0, "alien %d is hit" % i)
		else:
			assert_eq(_dealt(line[i]), 0.0, "alien %d is past its jumps" % i)


func test_fulgen_reaches_fliers_but_not_past_rock() -> void:
	await _drawn(FULGEN)
	var flier := _add_alien(Vector3(0.0, 0.0, -8.0), DARTER)
	await wait_seconds(1.0)
	assert_gt(flier.global_position.y, 2.0, "up in the air")
	await _attack_once()
	assert_gt(_dealt(flier), 0.0, "lightning goes to the alien itself")
	flier.free()
	var sheltered := _add_alien(Vector3(0.0, 0.0, -8.0))
	_add_box(Vector3(0.0, 1.5, -4.0), Vector3(4.0, 3.0, 0.5))
	await wait_physics_frames(2)
	await _attack_once()
	assert_eq(_dealt(sheltered), 0.0, "rock stops it")


func test_fulgen_strikes_the_ground_without_an_alien() -> void:
	await _drawn(FULGEN)
	var behind := _add_alien(Vector3(0.0, 0.0, 6.0))
	await _attack_once()
	assert_eq(_dealt(behind), 0.0)
	assert_eq(
		_player.arms.weapon.ammo.rounds, _player.arms.weapon.ammo.capacity() - 1, "it always fires"
	)


func test_nadir_well_pulls_aliens_in_holds_them_and_bursts() -> void:
	await _drawn(NADIR)
	var spot := Vector3(0.0, 0.0, -WELL.stick_reach)
	var near := _add_alien(spot + Vector3(3.0, 0.0, 0.0))
	var other := _add_alien(spot + Vector3(-2.0, 0.0, -1.5))
	var outside := _add_alien(spot + Vector3(0.0, 0.0, -WELL.blast_radius - 2.0))
	var start: Vector3 = outside.global_position
	await wait_physics_frames(1)
	await _attack_once()
	await wait_seconds(WELL.stick_reach / WELL.speed + 1.2)
	assert_eq(GravityWell.opened_by(_player).size(), 1, "opened")
	for alien: Alien in [near, other]:
		assert_true(alien.status.is_held())
		assert_lt(_flat_distance(alien.global_position, spot), 1.5, "pulled to the middle")
		assert_eq(_dealt(alien), 0.0, "no damage before it bursts")
	assert_false(outside.status.is_held())
	assert_lt(_flat_distance(outside.global_position, start), 0.05, "beyond its radius")
	await wait_seconds(WELL.hold_time)
	assert_eq(GravityWell.opened_by(_player).size(), 0, "burst")
	assert_gt(_dealt(near), NADIR_DAMAGE.damage * 0.5, "the burst")
	assert_gt(_dealt(other), NADIR_DAMAGE.damage * 0.5)
	assert_eq(_dealt(outside), 0.0)
	await wait_seconds(0.3)
	assert_false(near.status.is_held(), "free again")


func test_a_held_alien_does_not_leap() -> void:
	var alien := _add_alien(Vector3(0.0, 0.0, -4.0))
	alien.strain.detection_range = 30.0
	GravityWell.open(_arena, alien.global_position, 5.0, _hit(), 3.0, null)
	await wait_seconds(2.0)
	assert_eq(_player.health, _player.vitals.maximum(), "no pounce from inside the well")
	assert_lt(_flat_distance(alien.global_position, Vector3(0.0, 0.0, -4.0)), 0.8, "it stays")


func test_an_alien_wells_do_not_hold_is_only_slowed() -> void:
	var alien := _add_alien(Vector3(2.0, 0.0, -10.0))
	alien.strain.held_by_wells = false
	GravityWell.open(_arena, Vector3(0.0, 0.0, -10.0), 5.0, _hit(), 3.0, null)
	await wait_seconds(0.5)
	assert_true(alien.status.is_held(), "in the well")
	assert_eq(alien.status.speed(), AlienStatus.WELL_SLOW)
	assert_lt(_flat_distance(alien.global_position, Vector3(2.0, 0.0, -10.0)), 0.05, "not pulled")


func test_a_flier_sinks_low_in_a_well() -> void:
	var flier := _add_alien(Vector3(0.0, 0.0, -10.0), DARTER)
	await wait_seconds(1.0)
	assert_gt(flier.global_position.y, 2.0)
	GravityWell.open(_arena, Vector3(0.0, 0.0, -10.0), 5.0, _hit(), 3.0, null)
	await wait_seconds(1.0)
	assert_almost_eq(flier.global_position.y, AlienFlight.HELD_HEIGHT, 0.3)


func test_nadir_keeps_one_well_and_recharges_one_at_a_time() -> void:
	var nadir: Weapon = await _drawn(NADIR)
	var ammo := nadir.ammo as BatteryAmmo
	await _attack_once()
	await wait_seconds(WELL.stick_reach / WELL.speed + 0.3)
	var first: Array[GravityWell] = GravityWell.opened_by(_player)
	assert_eq(first.size(), 1)
	await wait_seconds(1.0 / NADIR.attack_rate)
	await _attack_once()
	assert_eq(GravityWell.opened_by(_player).size(), 0, "the next shot bursts the last well")
	await wait_seconds(WELL.stick_reach / WELL.speed + 0.3)
	assert_eq(GravityWell.opened_by(_player).size(), 1)
	assert_eq(ammo.rounds, 0)
	assert_false(ammo.can_attack())
	assert_false(ammo.refilling(), "it doesn't drain")
	await wait_seconds(BATTERY.recharge_delay + 1.0 / BATTERY.recharge_rate)
	assert_eq(ammo.rounds, 1, "one well back")
	assert_true(ammo.can_attack(), "it fires again before it's full")


func _drawn(weapon_type: WeaponType) -> Weapon:
	_player.loadout.assign(0, weapon_type)
	assert_eq(_player.arms.get_weapon_type(), weapon_type)
	await wait_seconds(weapon_type.draw_time + 0.05)
	return _player.arms.weapon


func _attack_once() -> void:
	Input.action_press(&"attack")
	await wait_physics_frames(1)
	Input.action_release(&"attack")
	await wait_physics_frames(1)


func _dealt(alien: Alien) -> float:
	return alien.max_health() - alien.health


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## A hit for wells opened by hand.
func _hit() -> Hit:
	return Hit.new(NADIR_DAMAGE.damage, NADIR_DAMAGE.stagger, 0.0, Vector3.FORWARD, Vector3.ZERO)


## An alien of `strain` standing still (it notices nobody) with a lot of health.
func _add_alien(at: Vector3, strain: AlienStrain = SWARMER) -> Alien:
	var alien := strain.spawn()
	alien.strain = alien.strain.duplicate() as AlienStrain
	alien.strain.max_health = 10000.0
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
