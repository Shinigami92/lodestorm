extends GutTest
## Clout (hold to charge a punch that throws the nearest alien into others, into rock harder) and
## Mantle (a field in front blocking blows and shots, also for those behind it, draining its charge
## until it breaks; a bash).

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const SPIT: AlienSpit = preload("res://game/aliens/strains/spitter/spit.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const CLOUT: WeaponType = preload("res://game/weapons/types/clout/clout.tres")
const MANTLE: WeaponType = preload("res://game/weapons/types/mantle/mantle.tres")
const PUNCH: PunchDelivery = preload("res://game/weapons/types/clout/delivery.tres")
const CLOUT_DAMAGE: DamageEffect = preload("res://game/weapons/types/clout/damage.tres")
const THROW: ThrowEffect = preload("res://game/weapons/types/clout/throw.tres")
const CHARGE: ChargeTrigger = preload("res://game/weapons/types/clout/trigger.tres")
const FIELD: FieldFeed = preload("res://game/weapons/types/mantle/feed.tres")
const GUARD: WeaponGuard = preload("res://game/weapons/types/mantle/guard.tres")
const BASH: DamageEffect = preload("res://game/weapons/types/mantle/damage.tres")

var _arena: Node3D
var _player: Player


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0))
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	for weapon_type: WeaponType in [CLOUT, MANTLE]:
		_player.arsenal.unlock(weapon_type)
	await wait_physics_frames(1)


func after_each() -> void:
	Input.action_release(&"attack")


func test_both_are_prototypes_and_melee() -> void:
	for weapon_type: WeaponType in [CLOUT, MANTLE]:
		assert_eq(weapon_type.origin, WeaponType.Origin.PROTOTYPE)
		assert_true(weapon_type.is_melee(), weapon_type.display_name)
	assert_eq(CLOUT.hold, WeaponType.Hold.FIST)
	assert_eq(MANTLE.hold, WeaponType.Hold.SHIELD)


func test_clout_punches_only_the_nearest_in_front() -> void:
	var clout: Weapon = await _drawn(CLOUT)
	var near := _add_alien(Vector3(0.0, 0.0, -1.2))
	var farther := _add_alien(Vector3(0.6, 0.0, -2.0))
	var aside := _add_alien(Vector3(-1.5, 0.0, -0.5))
	await wait_physics_frames(1)
	_punch(clout, 1.0)
	assert_almost_eq(_dealt(near), CLOUT_DAMAGE.damage, 0.01, "the nearest")
	assert_eq(_dealt(farther), 0.0, "only one")
	assert_eq(_dealt(aside), 0.0, "outside its arc")


func test_clout_full_charge_throws_the_alien_far_staggered() -> void:
	var clout: Weapon = await _drawn(CLOUT)
	var alien := _add_alien(Vector3(0.0, 0.0, -1.2))
	await wait_physics_frames(1)
	_punch(clout, 1.0)
	assert_true(alien.thrown.is_flying())
	assert_true(alien.is_staggered(), "can't attack while it flies")
	await wait_seconds(THROW.distance / THROW.speed + 0.3)
	assert_false(alien.thrown.is_flying())
	var flown: float = -alien.global_position.z - 1.2
	assert_almost_eq(flown, THROW.distance, 0.5, "thrown along the aim")
	assert_true(alien.is_staggered(), "still staggered after landing")


func test_clout_jab_only_shoves() -> void:
	var clout: Weapon = await _drawn(CLOUT)
	var alien := _add_alien(Vector3(0.0, 0.0, -1.2))
	await wait_physics_frames(1)
	_punch(clout, CHARGE.min_power)
	assert_almost_eq(_dealt(alien), CLOUT_DAMAGE.damage * CHARGE.min_power, 0.01)
	await wait_seconds(1.0)
	var flown: float = -alien.global_position.z - 1.2
	assert_almost_eq(flown, THROW.jab_distance, 0.4)


func test_clout_heavy_strains_fly_less_and_the_apex_not_at_all() -> void:
	var clout: Weapon = await _drawn(CLOUT)
	var heavy := _add_alien(Vector3(0.0, 0.0, -1.2))
	heavy.strain.knockback = 0.2
	await wait_physics_frames(1)
	_punch(clout, 1.0)
	await wait_seconds(1.0)
	assert_almost_eq(-heavy.global_position.z - 1.2, THROW.distance * 0.2, 0.4, "shoved")
	heavy.queue_free()
	var apex := _add_alien(Vector3(0.0, 0.0, -1.2))
	apex.strain.knockback = 0.05
	await wait_physics_frames(2)
	_punch(clout, 1.0)
	assert_false(apex.thrown.is_flying(), "not thrown")


func test_clout_thrown_alien_knocks_others_aside() -> void:
	var clout: Weapon = await _drawn(CLOUT)
	var thrown := _add_alien(Vector3(0.0, 0.0, -1.2))
	var in_the_way := _add_alien(Vector3(0.3, 0.0, -4.0))
	await wait_physics_frames(1)
	_punch(clout, 1.0)
	await wait_seconds(0.8)
	var share: float = CLOUT_DAMAGE.damage * THROW.passed_share
	assert_almost_eq(_dealt(in_the_way), share, 0.01, "half the punch")
	assert_false(in_the_way.thrown.is_flying(), "it doesn't fly on")
	assert_gt(in_the_way.global_position.x, 1.0, "knocked aside")
	assert_lt(thrown.global_position.z, -6.0, "the thrown one flew on")


func test_clout_into_rock_hits_harder_and_staggers_longer() -> void:
	var clout: Weapon = await _drawn(CLOUT)
	var alien := _add_alien(Vector3(0.0, 0.0, -1.2))
	_add_box(Vector3(0.0, 1.5, -4.0), Vector3(4.0, 3.0, 0.4))
	await wait_physics_frames(2)
	_punch(clout, 1.0)
	await wait_seconds(0.4)
	assert_false(alien.thrown.is_flying(), "stopped at the rock")
	assert_gt(alien.global_position.z, -4.0)
	var hit: float = CLOUT_DAMAGE.damage * (1.0 + THROW.wall_share)
	assert_almost_eq(_dealt(alien), hit, 0.01, "slammed into it")
	await wait_seconds(THROW.wall_stagger - 0.5)
	assert_true(alien.is_staggered())


func test_clout_charges_while_held_and_slows_the_player() -> void:
	var clout: Weapon = await _drawn(CLOUT)
	var alien := _add_alien(Vector3(0.0, 0.0, -1.2))
	await wait_physics_frames(1)
	Input.action_press(&"attack")
	await wait_seconds(CHARGE.charge_time + 0.1)
	assert_eq(clout.wind, 1.0, "fully charged")
	assert_eq(clout.move_share(), CHARGE.charging_move_share)
	assert_eq(_dealt(alien), 0.0, "nothing until let go")
	Input.action_release(&"attack")
	await wait_physics_frames(2)
	assert_almost_eq(_dealt(alien), CLOUT_DAMAGE.damage, 0.01)
	assert_eq(clout.move_share(), 1.0)


func test_mantle_blocks_a_blow_from_the_front_only() -> void:
	var mantle: Weapon = await _drawn(MANTLE)
	var ammo := mantle.ammo as FieldAmmo
	assert_true(mantle.field.is_up())
	assert_eq(mantle.move_share(), GUARD.move_share, "walks a little slower")
	var front := _add_alien(Vector3(0.0, 0.0, -1.2))
	var behind := _add_alien(Vector3(0.0, 0.0, 1.2))
	await wait_physics_frames(1)
	var health: float = _player.health
	front.strike(_player, 10.0)
	assert_eq(_player.health, health, "blocked")
	assert_almost_eq(ammo.share(), 1.0 - 10.0 / FIELD.charge, 0.001, "drained")
	behind.strike(_player, 10.0)
	assert_almost_eq(_player.health, health - 10.0, 0.01, "not from behind")


func test_mantle_field_breaks_and_comes_back() -> void:
	var mantle: Weapon = await _drawn(MANTLE)
	var ammo := mantle.ammo as FieldAmmo
	var front := _add_alien(Vector3(0.0, 0.0, -1.2))
	await wait_physics_frames(1)
	var health: float = _player.health
	front.strike(_player, FIELD.charge + 5.0)
	assert_almost_eq(_player.health, health - 5.0, 0.01, "the rest goes through")
	assert_true(ammo.is_broken())
	assert_false(mantle.field.is_up())
	front.strike(_player, 5.0)
	assert_almost_eq(_player.health, health - 10.0, 0.01, "down while broken")
	await wait_seconds(FIELD.break_time + 0.1)
	assert_false(ammo.is_broken())
	assert_eq(ammo.rounds, ammo.capacity(), "back full")


func test_mantle_field_recharges_after_a_while() -> void:
	var mantle: Weapon = await _drawn(MANTLE)
	var ammo := mantle.ammo as FieldAmmo
	assert_eq(ammo.absorb(50.0), 0.0)
	await wait_seconds(FIELD.recharge_delay * 0.5)
	assert_almost_eq(ammo.share(), 0.5, 0.01, "not yet")
	await wait_seconds(FIELD.recharge_delay * 0.5 + 50.0 / FIELD.recharge_rate + 0.2)
	assert_almost_eq(ammo.share(), 1.0, 0.01)


func test_mantle_stops_spit_aimed_right_behind_it() -> void:
	var mantle: Weapon = await _drawn(MANTLE)
	var spitter := _add_alien(Vector3(0.0, 0.0, -9.0))
	await wait_physics_frames(1)
	var glob := AcidGlob.launch(spitter, SPIT, Vector3(0.0, 0.8, -8.5), Vector3(0.0, 0.0, 1.0))
	await wait_seconds(glob.flight_time + 0.2)
	assert_false(is_instance_valid(glob), "gone")
	assert_lt((mantle.ammo as FieldAmmo).share(), 1.0, "stopped by the field")
	for node: Node in _arena.get_children():
		assert_false(node is AcidPuddle, "it never landed")


func test_mantle_heavy_blow_shoves_back_and_stops_the_charge() -> void:
	await _drawn(MANTLE)
	var brute := _add_alien(Vector3(0.0, 0.0, -1.5))
	await wait_physics_frames(1)
	var start: Vector3 = _player.global_position
	var health: float = _player.health
	Alien.hurt(_player, 30.0, brute.global_position, brute, true)
	assert_eq(_player.health, health)
	assert_true(brute.status.blocked, "its charge ends dazed")
	await wait_seconds(GUARD.shove_time + 0.2)
	assert_gt(_player.global_position.z - start.z, GUARD.shove * 0.7, "shoved back")


func test_mantle_bash_staggers_and_leaves_an_opening() -> void:
	var mantle: Weapon = await _drawn(MANTLE)
	var alien := _add_alien(Vector3(0.0, 0.0, -1.2))
	await wait_physics_frames(1)
	Input.action_press(&"attack")
	await wait_physics_frames(1)
	Input.action_release(&"attack")
	assert_almost_eq(_dealt(alien), BASH.damage, 0.01)
	assert_true(alien.is_staggered())
	assert_true(mantle.field.is_up(), "blocks during the bash")
	await wait_seconds(GUARD.open_after + 0.05)
	assert_false(mantle.field.is_up(), "open while the arm comes back")
	await wait_seconds(GUARD.open_time)
	assert_true(mantle.field.is_up())


func _punch(weapon: Weapon, power: float) -> void:
	weapon.power = power
	PUNCH.attack(weapon)
	weapon.power = 1.0


func _drawn(weapon_type: WeaponType) -> Weapon:
	_player.loadout.assign(0, weapon_type)
	assert_eq(_player.get_weapon_type(), weapon_type)
	await wait_seconds(weapon_type.draw_time + 0.05)
	return _player.weapon


func _dealt(alien: Alien) -> float:
	return alien.max_health() - alien.health


## An alien standing still (it notices nobody) with a lot of health.
func _add_alien(at: Vector3) -> Alien:
	var alien := SWARMER.spawn()
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
