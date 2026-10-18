extends GutTest

const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const SHOTGUN: WeaponType = preload("res://game/weapons/types/shotgun.tres")
const HAMMER: WeaponType = preload("res://game/weapons/types/hammer.tres")

var _arena: Node3D
var _player: Player


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0))
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	_player.arsenal.unlock(SHOTGUN)
	await wait_physics_frames(1)


func after_each() -> void:
	Input.action_release(&"attack")


func test_hammer_hits_every_alien_in_front_within_reach() -> void:
	var hammer: MeleeWeapon = _equip(HAMMER) as MeleeWeapon
	var reach: float = hammer.settings.reach
	# The player faces -Z.
	var front := _add_alien(Vector3(0.0, 0.0, -reach + 0.3))
	var side := _add_alien(Vector3(0.8, 0.0, -1.2))
	var behind := _add_alien(Vector3(0.0, 0.0, 1.5))
	var far := _add_alien(Vector3(0.0, 0.0, -reach - 3.0))
	watch_signals(hammer)
	await _attack_once()
	assert_signal_emit_count(hammer, "swung", 1)
	var hits: Array = get_signal_parameters(hammer, "swung")[0]
	assert_has(hits, front)
	assert_has(hits, side)
	assert_does_not_have(hits, behind)
	assert_does_not_have(hits, far)
	assert_lt(front.health, front.max_health())
	assert_eq(behind.health, behind.max_health())


func test_upgraded_hammer_hits_harder() -> void:
	var hammer: MeleeWeapon = _equip(HAMMER) as MeleeWeapon
	_player.upgrades.raise(HAMMER.upgrade)
	var alien := SWARMER.spawn()
	alien.strain = alien.strain.duplicate() as AlienStrain
	alien.strain.max_health = 1000.0
	alien.position = Vector3(0.0, 0.0, -1.5)
	_arena.add_child(alien)
	await _attack_once()
	var damage: float = hammer.settings.damage * HAMMER.upgrade.levels[0].multiplier
	assert_eq(alien.health, alien.strain.max_health - damage)


func test_hammer_does_not_hit_through_walls() -> void:
	var hammer: MeleeWeapon = _equip(HAMMER) as MeleeWeapon
	_add_box(Vector3(0.0, 1.0, -1.0), Vector3(3.0, 2.0, 0.2))
	var alien := _add_alien(Vector3(0.0, 0.0, -2.0))
	watch_signals(hammer)
	await _attack_once()
	assert_signal_emit_count(hammer, "swung", 1)
	assert_eq(alien.health, alien.strain.max_health)


func test_hammer_swings_at_attack_rate() -> void:
	var hammer: MeleeWeapon = _equip(HAMMER) as MeleeWeapon
	watch_signals(hammer)
	Input.action_press(&"attack")
	await wait_physics_frames(Engine.physics_ticks_per_second * 2)
	var rate: float = hammer.settings.attack_rate * 2.0
	var swings: int = get_signal_emit_count(hammer, "swung")
	assert_between(float(swings), rate, rate + 1.0)


func test_shotgun_fires_a_fan_of_pellets() -> void:
	var shotgun: RangedWeapon = _equip(SHOTGUN) as RangedWeapon
	var fired: Array[Projectile] = []
	_arena.child_entered_tree.connect(
		func(node: Node) -> void:
			if node is Projectile:
				fired.append(node as Projectile)
	)
	await _attack_once()
	assert_eq(fired.size(), shotgun.settings.pellets)
	var widest: float = 0.0
	for projectile: Projectile in fired:
		var direction: Vector3 = projectile.velocity.normalized()
		widest = maxf(widest, rad_to_deg(direction.angle_to(_player.aim.direction)))
		assert_almost_eq(projectile.damage, shotgun.settings.damage, 0.001)
	assert_almost_eq(widest, shotgun.settings.spread * 0.5, 0.5)


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
