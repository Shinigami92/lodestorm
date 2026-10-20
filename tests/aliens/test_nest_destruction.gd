extends GutTest
## Destroyable nests (see GAME_DESIGN.md, Combat & aliens): health and armor, the bursts and their
## warning, the stages, the collapse, the hive's answer and the target lock.

const NEST_SCENE: PackedScene = preload("res://game/aliens/nest/alien_nest.tscn")
const TEST_MAP := preload("res://tests/support/test_map.gd")
const PROJECTILE: PackedScene = preload("res://game/weapons/projectile.tscn")
const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const WARDEN: AlienStrain = preload("res://game/aliens/strains/warden/warden.tres")
const GNAWER: AlienStrain = preload("res://game/aliens/strains/gnawer/gnawer.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")

var _map: Node3D
var _mission: Mission
var _player: Player
var _ship: Ship
var _nest: AlienNest


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_mission = _map.get_node("Mission") as Mission
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	# The location's own nests would get in the way.
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		nest.queue_free()
	_nest = _add_nest(Vector3(55.0, 0.0, 0.0), 2)
	watch_signals(_nest)
	await wait_physics_frames(2)


func test_health_scales_like_the_aliens_and_per_player() -> void:
	var tier_factor: float = _mission.settings.alien_health_at(_mission.tier())
	assert_almost_eq(_nest.body.max_health, _nest.settings.health * tier_factor, 1e-3)
	assert_eq(_nest.body.health, _nest.body.max_health, "unhurt")
	var teammate := Node.new()
	teammate.add_to_group(Player.GROUP)
	add_child_autofree(teammate)
	assert_almost_eq(
		_nest.max_health(),
		_nest.settings.health * tier_factor * (1.0 + _nest.settings.health_per_player),
		1e-3,
		"a second player adds their share"
	)


func test_armor_takes_its_share_of_every_hit() -> void:
	var armor: float = _nest.settings.armor
	assert_eq(_nest.body.armor, armor)
	var health: float = _nest.body.health
	assert_almost_eq(_nest.body.take_hit(_hit(10.0)), 10.0 - armor, 1e-4)
	assert_almost_eq(_nest.body.health, health - (10.0 - armor), 1e-4)
	assert_almost_eq(
		_nest.body.take_hit(_hit(armor)), armor * Alien.MIN_DAMAGE_SHARE, 1e-4, "at least a share"
	)


func test_shots_and_swings_hurt_it() -> void:
	# Its guards would catch the shot.
	for guard: Alien in _aliens():
		guard.free()
	var health: float = _nest.body.health
	var projectile := PROJECTILE.instantiate() as Projectile
	projectile.velocity = Vector3.FORWARD * 30.0
	projectile.max_distance = 25.0
	projectile.damage = 10.0
	_map.add_child(projectile)
	projectile.global_position = _nest.global_position + Vector3(0.0, 0.8, 5.0)
	await wait_physics_frames(20)
	assert_lt(_nest.body.health, health, "a shot hurts it")
	health = _nest.body.health
	_player.loadout.assign(0, DRAY)
	# Harl, which it replaced, goes at the end of the frame.
	await wait_physics_frames(1)
	var dray: Weapon = _player.weapon
	_stand_at(Vector3(0.0, 0.0, (DRAY.delivery as SwingDelivery).reach + 1.0))
	dray.aim_direction = Vector3.FORWARD
	dray.aim_target = null
	DRAY.delivery.attack(dray)
	assert_lt(_nest.body.health, health, "a swing reaches its edge")


func test_a_burst_warns_then_spews_hunters_and_cracks_it() -> void:
	_nest.settings.burst_warning = 0.5
	var guards: int = _aliens().size()
	_damage_share(1.0 / 3.0)
	assert_true(_nest.is_warning(), "its mouth swells first")
	assert_eq(_aliens().size(), guards, "nothing yet")
	# One after another.
	await _wait_physics(0.6 + (_nest.settings.burst_aliens - 1) * _nest.settings.hatch_gap)
	assert_false(_nest.is_warning())
	assert_eq(_nest.get_hunters().size(), _nest.settings.burst_aliens, "then it spews hunters")
	assert_eq(_nest.stage, 1)
	var cracks := _nest.find_child("Cracks1", true, false) as GeometryInstance3D
	assert_not_null(cracks, "the model has cracks")
	if cracks:
		assert_true(cracks.visible, "its first cracks open")
		var next := _nest.find_child("Cracks2", true, false) as GeometryInstance3D
		assert_false(next and next.visible, "not the second ones yet")


func test_three_stages_then_it_collapses() -> void:
	_nest.settings.burst_warning = 0.1
	_damage_share(1.0 / 3.0)
	await _wait_physics(0.2)
	_damage_share(1.0 / 3.0)
	await _wait_physics(0.2)
	assert_eq(_nest.stage, 2, "a burst at two thirds and at one third")
	assert_true(PlayerAim.is_lockable(_nest.body))
	_damage_share(1.0 / 3.0)
	assert_signal_emitted(_nest, "destroyed")
	assert_true(_nest.is_destroyed())
	assert_true(_nest.body.dead)
	assert_false(_nest.is_in_group(AlienNest.GROUP), "a husk is no nest")
	assert_false(PlayerAim.is_lockable(_nest.body), "nor a target")
	assert_eq(_nest.body.take_hit(_hit(10.0)), 0.0, "and takes no more hits")
	assert_true(is_instance_valid(_nest), "the husk stays")
	await _wait_physics(_nest.settings.collapse_time + 0.1)
	var model := _nest.get_node("Model") as Node3D
	assert_lt(model.scale.y, 0.6, "collapsed")


func test_a_big_hit_through_both_bursts_still_bursts_twice() -> void:
	_nest.settings.burst_warning = 0.1
	_damage_share(0.7)
	await _wait_physics(0.3 + (2 * _nest.settings.burst_aliens - 1) * _nest.settings.hatch_gap)
	assert_eq(_nest.stage, 2)
	assert_eq(_nest.get_hunters().size(), 2 * _nest.settings.burst_aliens)


func test_destroyed_it_sends_no_more_hunters_or_raiders() -> void:
	_nest.settings.hunter_interval_start = 0.2
	_nest.hunter_cooldown = 0.2
	await _start_mission()
	await _wait_physics(0.3)
	var out: Array[Alien] = _nest.get_hunters()
	assert_eq(out.size(), 1)
	_damage_share(1.0)
	await _wait_physics(0.6)
	assert_eq(_nest.get_hunters(), out, "its hunters out stay, no new ones come")
	_nest.raider_cooldown = 0.0
	_nest.settings.raider_interval_start = 0.1
	var node: OreNode = _mission.location.get_node("OreNodes/KyriteA") as OreNode
	node.place_miner(_player.miner_scene)
	await _wait_physics(0.4)
	assert_eq(_nest.get_raiders().size(), 0, "nor raiders")


func test_the_other_nests_surge() -> void:
	var other: AlienNest = _add_nest(Vector3(-55.0, 0.0, 0.0), 0)
	await _start_mission()
	assert_eq(other.get_hunters().size(), 0)
	_damage_share(1.0)
	assert_eq(other.get_hunters().size(), 1, "its next pack, right away")
	assert_eq(_nest.get_hunters().size(), 0, "not from the husk")


func test_its_guards_come_to_defend_it() -> void:
	var guards: Array[Alien] = _aliens()
	assert_eq(guards.size(), 2)
	# Outside their sight, inside their leash.
	_stand_at(Vector3(0.0, 0.0, WARDEN.detection_range + 4.0))
	await _wait_physics(0.2)
	for guard: Alien in guards:
		assert_null(guard.target, "it doesn't see the player")
	_nest.body.take_hit(_hit(10.0, _player))
	await _wait_physics(0.2)
	for guard: Alien in guards:
		assert_eq(guard.target, _player, "it goes for the attacker")
	_damage_share(1.0)
	for guard: Alien in guards:
		assert_null(guard.status.defending, "a husk needs no defending")


func test_the_lock_takes_a_nest_but_an_alien_first() -> void:
	for guard: Alien in _aliens():
		guard.free()
	_stand_at(Vector3(0.0, 0.0, 12.0))
	_player.aim.with_stick(Vector3.FORWARD)
	assert_eq(_player.aim.target, _nest.body, "the nest it points at")
	var alien: Alien = _nest.hatch(Alien.Role.GUARD, WARDEN)
	alien.global_position = _nest.global_position + Vector3(0.0, 0.0, 4.0)
	await wait_physics_frames(1)
	_player.aim.with_stick(Vector3.FORWARD)
	assert_eq(_player.aim.target, alien, "an alien beside it first")
	var camera: Camera3D = get_viewport().get_camera_3d()
	alien.free()
	_player.aim.at_screen_position(camera, camera.unproject_position(_nest.body.get_aim_point()))
	assert_eq(_player.aim.target, _nest.body, "under the cursor too")


func test_the_debug_shortcut_takes_a_stage_off_every_nest() -> void:
	var other: AlienNest = _add_nest(Vector3(-55.0, 0.0, 0.0), 0)
	await wait_physics_frames(1)
	DebugOverlay._damage_nests()
	for nest: AlienNest in [_nest, other]:
		assert_almost_eq(nest.body.health, nest.body.max_health * 2.0 / 3.0, 1e-3)
		assert_true(nest.is_warning())


## A nest with packs of one swarmer and `guards` guards at `offset` from the ship.
func _add_nest(offset: Vector3, guards: int) -> AlienNest:
	var nest := NEST_SCENE.instantiate() as AlienNest
	nest.settings = nest.settings.duplicate() as AlienNestSettings
	nest.settings.guards = guards
	var pack := AlienPack.new()
	pack.members = {SWARMER: 1}
	var hive := AlienHive.new()
	hive.strains = [SWARMER, WARDEN, GNAWER]
	hive.packs = [pack]
	nest.table = hive.table(1)
	nest.position = _ship.to_global(offset)
	_map.add_child(nest)
	return nest


## Takes `share` of its health off the nest.
func _damage_share(share: float) -> void:
	_nest.body.take_damage(_nest.body.max_health * share + 1e-3)


func _hit(damage: float, attacker: Node = null) -> Hit:
	return Hit.new(damage, 0.0, 0.0, Vector3.FORWARD, _nest.body.get_aim_point(), attacker)


## Puts the player at `offset` from the nest.
func _stand_at(offset: Vector3) -> void:
	_player.global_position = _nest.global_position + offset
	_player.reset_physics_interpolation()


func _start_mission() -> void:
	_mission.state = Mission.State.OPEN
	_player.global_position = _ship.to_global(Vector3(22.0, 0.0, 0.0))
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_mission.state, Mission.State.RUNNING)


func _aliens() -> Array[Alien]:
	var aliens: Array[Alien] = []
	aliens.assign(get_tree().get_nodes_in_group(Alien.GROUP).filter(_nest.is_ancestor_of))
	return aliens


## Waits `seconds` of physics time (see test_alien_nest.gd).
func _wait_physics(seconds: float) -> void:
	await wait_physics_frames(roundi(seconds * Engine.physics_ticks_per_second))
