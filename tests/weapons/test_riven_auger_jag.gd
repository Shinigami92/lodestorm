extends GutTest
## Riven (a chain of slashes, the last lunging), Auger (a thrust through a line, then drilling into
## the first alien) and Jag (a held saw staggering and slowing what it touches).

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const RIVEN: WeaponType = preload("res://game/weapons/types/riven/riven.tres")
const AUGER: WeaponType = preload("res://game/weapons/types/auger/auger.tres")
const JAG: WeaponType = preload("res://game/weapons/types/jag/jag.tres")
const CHAIN: SwingDelivery = preload("res://game/weapons/types/riven/delivery.tres")
const RIVEN_DAMAGE: DamageEffect = preload("res://game/weapons/types/riven/damage.tres")
const THRUST: ThrustDelivery = preload("res://game/weapons/types/auger/delivery.tres")
const AUGER_DAMAGE: DamageEffect = preload("res://game/weapons/types/auger/damage.tres")
const DRILL: DrillTrigger = preload("res://game/weapons/types/auger/trigger.tres")
const SAW: SwingDelivery = preload("res://game/weapons/types/jag/delivery.tres")
const SLOW: SlowEffect = preload("res://game/weapons/types/jag/slow.tres")

var _arena: Node3D
var _player: Player


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0))
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	for weapon_type: WeaponType in [RIVEN, AUGER, JAG]:
		_player.arsenal.unlock(weapon_type)
	await wait_physics_frames(1)


func after_each() -> void:
	Input.action_release(&"attack")


func test_riven_slashes_twice_then_lunges_for_double() -> void:
	var riven: Weapon = await _drawn(RIVEN)
	var alien := _add_alien(Vector3(0.0, 0.0, -1.5))
	var aside := _add_alien(Vector3(2.0, 0.0, -0.5))
	await wait_physics_frames(1)
	_slash(riven)
	_slash(riven)
	var full: float = RIVEN_DAMAGE.damage
	assert_almost_eq(_dealt(alien), full * 2.0, 0.01, "two slashes")
	assert_eq(_dealt(aside), 0.0, "a narrow arc")
	assert_eq(riven.chain, 2)
	var start: Vector3 = _player.global_position
	_slash(riven)
	assert_almost_eq(_dealt(alien), full * (2.0 + CHAIN.lunge_power), 0.01, "the lunge hits harder")
	await wait_seconds(CHAIN.lunge_time + 0.2)
	var moved: float = _flat_distance(_player.global_position, start)
	assert_gt(moved, 0.3, "it lunged")
	assert_lt(moved, 1.5 - SwingDelivery.LUNGE_STOP + 0.3, "stopping short of the alien")
	_slash(riven)
	assert_eq(riven.chain, 1, "the chain starts over")


func test_riven_chain_starts_over_after_a_pause() -> void:
	var riven: Weapon = await _drawn(RIVEN)
	var alien := _add_alien(Vector3(0.0, 0.0, -1.5))
	await wait_physics_frames(1)
	_slash(riven)
	_slash(riven)
	riven.since_attack = CHAIN.combo_gap + 0.1
	_slash(riven)
	assert_eq(riven.chain, 1)
	assert_almost_eq(_dealt(alien), RIVEN_DAMAGE.damage * 3.0, 0.01, "no lunge")


func test_riven_lunges_its_distance_hitting_along_the_way_but_not_past_rock() -> void:
	var riven: Weapon = await _drawn(RIVEN)
	var far := _add_alien(Vector3(0.6, 0.0, -CHAIN.lunge - 1.2))
	var behind := _add_alien(Vector3(0.0, 0.0, 2.0))
	await wait_physics_frames(1)
	var start: Vector3 = _player.global_position
	riven.chain = CHAIN.combo - 1
	riven.since_attack = 0.0
	_slash(riven)
	assert_almost_eq(_dealt(far), RIVEN_DAMAGE.damage * CHAIN.lunge_power, 0.01)
	assert_eq(_dealt(behind), 0.0)
	await wait_seconds(CHAIN.lunge_time + 0.2)
	var moved: float = _flat_distance(_player.global_position, start)
	assert_gt(moved, CHAIN.lunge - SwingDelivery.LUNGE_STOP - 0.5, "nearly up to the alien")
	_add_box(_player.global_position + Vector3(0.0, 1.5, -1.5), Vector3(4.0, 3.0, 0.4))
	await wait_physics_frames(2)
	start = _player.global_position
	riven.chain = CHAIN.combo - 1
	riven.since_attack = 0.0
	_slash(riven)
	await wait_seconds(CHAIN.lunge_time + 0.2)
	assert_lt(_flat_distance(_player.global_position, start), 0.8, "rock stops it short")


func test_auger_thrust_pierces_a_line_up_to_its_reach() -> void:
	await _drawn(AUGER)
	var first := _add_alien(Vector3(0.0, 0.0, -1.5))
	var second := _add_alien(Vector3(0.2, 0.0, -3.5))
	var aside := _add_alien(Vector3(1.6, 0.0, -2.0))
	var beyond := _add_alien(Vector3(0.0, 0.0, -THRUST.reach - 1.0))
	await wait_physics_frames(1)
	await _attack_once()
	assert_almost_eq(_dealt(first), AUGER_DAMAGE.damage, 0.01)
	assert_almost_eq(_dealt(second), AUGER_DAMAGE.damage, 0.01, "pierced")
	assert_eq(_dealt(aside), 0.0, "a narrow line")
	assert_eq(_dealt(beyond), 0.0, "out of reach")


func test_auger_thrust_stops_at_rock() -> void:
	await _drawn(AUGER)
	var sheltered := _add_alien(Vector3(0.0, 0.0, -3.0))
	_add_box(Vector3(0.0, 1.5, -1.8), Vector3(4.0, 3.0, 0.4))
	await wait_physics_frames(2)
	await _attack_once()
	assert_eq(_dealt(sheltered), 0.0)


func test_auger_held_drills_the_first_alien_harder_and_harder() -> void:
	var auger: Weapon = await _drawn(AUGER)
	var first := _add_alien(Vector3(0.0, 0.0, -1.5))
	var second := _add_alien(Vector3(0.0, 0.0, -3.0))
	await wait_physics_frames(1)
	Input.action_press(&"attack")
	await wait_physics_frames(2)
	assert_eq(auger.latched, first, "latched on to the first")
	assert_eq(auger.move_share(), DRILL.drilling_move_share, "walks slower while drilling")
	await wait_seconds(THRUST.ramp_time + 0.5)
	assert_almost_eq(THRUST.ramped(auger), 1.0, 0.01, "fully ramped")
	var drilled: float = _dealt(first) - AUGER_DAMAGE.damage
	var flat: float = AUGER_DAMAGE.damage * THRUST.drill_damage * THRUST.drill_rate
	assert_gt(drilled, flat * (THRUST.ramp_time + 0.5) * 1.5, "the ramp adds up")
	assert_almost_eq(_dealt(second), AUGER_DAMAGE.damage, 0.01, "only the thrust")
	Input.action_release(&"attack")
	await wait_physics_frames(2)
	assert_null(auger.latched, "letting go ends the drill")
	assert_eq(auger.move_share(), 1.0)


func test_auger_drill_lets_go_out_of_reach() -> void:
	var auger: Weapon = await _drawn(AUGER)
	var alien := _add_alien(Vector3(0.0, 0.0, -1.5))
	await wait_physics_frames(1)
	Input.action_press(&"attack")
	await wait_physics_frames(2)
	assert_eq(auger.latched, alien)
	alien.global_position = Vector3(0.0, 0.0, -THRUST.reach - 3.0)
	await wait_physics_frames(3)
	assert_null(auger.latched)
	var dealt: float = _dealt(alien)
	await wait_seconds(0.5)
	assert_eq(_dealt(alien), dealt, "no more drilling while still held")


func test_jag_grinds_staggers_and_slows_what_is_in_front() -> void:
	await _drawn(JAG)
	var front := _add_alien(Vector3(0.3, 0.0, -1.5))
	var aside := _add_alien(Vector3(1.8, 0.0, 0.5))
	var far := _add_alien(Vector3(0.0, 0.0, -SAW.reach - 1.0))
	await wait_physics_frames(1)
	Input.action_press(&"attack")
	var staggered: bool = false
	var slowed: bool = false
	for _i: int in 60:
		await wait_physics_frames(1)
		staggered = staggered or front.is_staggered()
		slowed = slowed or front.status.speed() == SLOW.factor
	assert_gt(_dealt(front), 0.0)
	assert_true(staggered, "it staggers a swarmer")
	assert_true(slowed, "it slows what it touches")
	assert_eq(_dealt(aside), 0.0, "outside its width")
	assert_eq(_dealt(far), 0.0, "out of reach")
	assert_lt(_player.weapon.move_share(), 0.6, "walks slower while sawing")
	Input.action_release(&"attack")
	await wait_seconds(SLOW.seconds + 0.1)
	assert_eq(front.status.speed(), 1.0, "the slow wears off")


## One slash of `weapon` straight away, as the next of its chain.
func _slash(weapon: Weapon) -> void:
	weapon.type.delivery.attack(weapon)
	weapon.power = 1.0
	weapon.since_attack = 0.0


func _drawn(weapon_type: WeaponType) -> Weapon:
	_player.loadout.assign(0, weapon_type)
	assert_eq(_player.get_weapon_type(), weapon_type)
	await wait_seconds(weapon_type.draw_time + 0.05)
	return _player.weapon


func _attack_once() -> void:
	Input.action_press(&"attack")
	await wait_physics_frames(1)
	Input.action_release(&"attack")
	await wait_physics_frames(1)


func _dealt(alien: Alien) -> float:
	return alien.max_health() - alien.health


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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
