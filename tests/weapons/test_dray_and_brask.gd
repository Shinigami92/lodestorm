extends GutTest

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")
const SWING: SwingDelivery = preload("res://game/weapons/types/dray/delivery.tres")
const DRAY_DAMAGE: DamageEffect = preload("res://game/weapons/types/dray/damage.tres")
const PELLETS: ProjectileDelivery = preload("res://game/weapons/types/brask/delivery.tres")
const BRASK_DAMAGE: DamageEffect = preload("res://game/weapons/types/brask/damage.tres")

var _arena: Node3D
var _player: Player


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0))
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	_player.arsenal.unlock(BRASK)
	await wait_physics_frames(1)


func after_each() -> void:
	Input.action_release(&"attack")


func test_dray_hits_every_alien_in_front_within_reach() -> void:
	var dray: Weapon = _equip(DRAY)
	var reach: float = SWING.reach
	# The player faces -Z.
	var front := _add_alien(Vector3(0.0, 0.0, -reach + 0.3))
	var side := _add_alien(Vector3(0.8, 0.0, -1.2))
	var behind := _add_alien(Vector3(0.0, 0.0, 1.5))
	var far := _add_alien(Vector3(0.0, 0.0, -reach - 3.0))
	watch_signals(dray)
	await _attack_once()
	assert_signal_emit_count(dray, "swung", 1)
	var hits: Array = get_signal_parameters(dray, "swung")[0]
	assert_has(hits, front)
	assert_has(hits, side)
	assert_does_not_have(hits, behind)
	assert_does_not_have(hits, far)
	assert_lt(front.health, front.max_health())
	assert_eq(behind.health, behind.max_health())


func test_upgraded_dray_hits_harder() -> void:
	_equip(DRAY)
	_player.upgrades.raise(DRAY.get_part(WeaponPart.Stat.DAMAGE))
	var alien := SWARMER.spawn()
	alien.strain = alien.strain.duplicate() as AlienStrain
	alien.strain.max_health = 1000.0
	alien.position = Vector3(0.0, 0.0, -1.5)
	_arena.add_child(alien)
	await _attack_once()
	var damage: float = (
		DRAY_DAMAGE.damage * DRAY.get_part(WeaponPart.Stat.DAMAGE).levels[0].multiplier
	)
	assert_eq(alien.health, alien.strain.max_health - damage)


func test_wider_arc_reaches_aliens_further_to_the_side() -> void:
	var dray: Weapon = _equip(DRAY)
	# 75 degrees off the front: outside the 120 degree swing, inside 165 (MK4).
	var side := _add_alien(Vector3(sin(deg_to_rad(75.0)), 0.0, -cos(deg_to_rad(75.0))) * 2.0)
	watch_signals(dray)
	await _attack_once()
	var first: Array = get_signal_parameters(dray, "swung", 0)[0]
	assert_does_not_have(first, side)
	for i: int in 3:
		_player.upgrades.raise(DRAY.get_part(WeaponPart.Stat.ARC))
	assert_almost_eq(rad_to_deg(SWING.arc_of(dray)), 165.0, 0.1)
	await wait_seconds(1.0 / dray.attack_rate())
	await _attack_once()
	var second: Array = get_signal_parameters(dray, "swung", 1)[0]
	assert_has(second, side)


func test_dray_does_not_hit_through_walls() -> void:
	var dray: Weapon = _equip(DRAY)
	_add_box(Vector3(0.0, 1.0, -1.0), Vector3(3.0, 2.0, 0.2))
	var alien := _add_alien(Vector3(0.0, 0.0, -2.0))
	watch_signals(dray)
	await _attack_once()
	assert_signal_emit_count(dray, "swung", 1)
	assert_eq(alien.health, alien.strain.max_health)


func test_dray_swings_at_attack_rate() -> void:
	var dray: Weapon = _equip(DRAY)
	watch_signals(dray)
	Input.action_press(&"attack")
	await wait_physics_frames(Engine.physics_ticks_per_second * 2)
	var rate: float = DRAY.attack_rate * 2.0
	var swings: int = get_signal_emit_count(dray, "swung")
	assert_between(float(swings), rate, rate + 1.0)


func test_brask_fires_a_fan_of_pellets() -> void:
	_equip(BRASK)
	var fired: Array[Projectile] = _watch_projectiles()
	await _attack_once()
	assert_eq(fired.size(), PELLETS.pellets)
	var widest: float = 0.0
	for projectile: Projectile in fired:
		var direction: Vector3 = projectile.velocity.normalized()
		widest = maxf(widest, rad_to_deg(direction.angle_to(_player.aim.direction)))
		assert_almost_eq(projectile.damage, BRASK_DAMAGE.damage, 0.001)
	assert_almost_eq(widest, PELLETS.spread * 0.5, 0.5)


func test_brask_pellets_part_adds_a_pellet_per_level_in_the_same_fan() -> void:
	for i: int in 2:
		_player.upgrades.raise(BRASK.get_part(WeaponPart.Stat.PELLETS))
	_equip(BRASK)
	var fired: Array[Projectile] = _watch_projectiles()
	await _attack_once()
	assert_eq(fired.size(), PELLETS.pellets + 2)
	var widest: float = 0.0
	for projectile: Projectile in fired:
		var direction: Vector3 = projectile.velocity.normalized()
		widest = maxf(widest, rad_to_deg(direction.angle_to(_player.aim.direction)))
	assert_almost_eq(widest, PELLETS.spread * 0.5, 0.5)


func _watch_projectiles() -> Array[Projectile]:
	var fired: Array[Projectile] = []
	_arena.child_entered_tree.connect(
		func(node: Node) -> void:
			if node is Projectile:
				fired.append(node as Projectile)
	)
	return fired


func _equip(weapon_type: WeaponType) -> Weapon:
	_player.loadout.assign(0, weapon_type)
	assert_eq(_player.get_weapon_type(), weapon_type)
	return _player.weapon


func _attack_once() -> void:
	Input.action_press(&"attack")
	await wait_physics_frames(1)
	Input.action_release(&"attack")
	await wait_physics_frames(1)


func _add_alien(at: Vector3) -> Alien:
	var alien := SWARMER.spawn()
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
