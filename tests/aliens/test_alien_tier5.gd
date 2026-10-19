extends GutTest
## The strains from tier 5 on and the apex: the darter (flying, its dive), the stalker (hiding, its
## ambush, its hooks, hit and run), the skimmer (circling, spitting on the move) and the Ravager
## (roaming, shedding swarmers, shaking the ground).

const DARTER: AlienStrain = preload("res://game/aliens/strains/darter/darter.tres")
const STALKER: AlienStrain = preload("res://game/aliens/strains/stalker/stalker.tres")
const SKIMMER: AlienStrain = preload("res://game/aliens/strains/skimmer/skimmer.tres")
const RAVAGER: AlienStrain = preload("res://game/aliens/strains/ravager/ravager.tres")
const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const HIVE: AlienHive = preload("res://game/aliens/hive/hive.tres")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")

var _arena: Node3D
var _player: Player


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	_add_box(Vector3(200.0, 1.0, 200.0), Vector3(0.0, -0.5, 0.0))
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	await wait_physics_frames(1)


func test_the_darter_flies_at_its_height_and_over_rock() -> void:
	var low: Alien = _still(DARTER, Vector3(30.0, 0.0, 0.0))
	_add_box(Vector3(6.0, 4.0, 6.0), Vector3(-30.0, 2.0, 0.0))
	var high: Alien = _still(DARTER, Vector3(-30.0, 4.0, 0.0))
	await _wait_physics(1.5)
	assert_almost_eq(low.global_position.y, DARTER.flight_height, 0.3, "above the ground")
	assert_almost_eq(high.global_position.y, 4.0 + DARTER.flight_height, 0.3, "above the rock")


func test_only_aimed_shots_reach_a_flying_darter() -> void:
	var darter: Alien = _still(DARTER, Vector3(10.0, 0.0, 0.0))
	await _wait_physics(1.5)
	var space: PhysicsDirectSpaceState3D = darter.get_world_3d().direct_space_state
	var flat := PhysicsRayQueryParameters3D.create(
		Vector3(5.0, 1.2, 0.0), Vector3(15.0, 1.2, 0.0), PhysicsLayers.SHOTS
	)
	assert_true(space.intersect_ray(flat).is_empty(), "flat shots fly under it")
	var aimed := PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 1.2, 0.0), darter.get_aim_point(), PhysicsLayers.SHOTS
	)
	aimed.exclude = [_player.get_rid()]
	var hit: Dictionary = space.intersect_ray(aimed)
	assert_eq(hit.get("collider") as Object, darter as Object, "locked shots hit it")
	assert_true(PlayerAim.is_lockable(darter))


func test_the_dive_shows_its_line_stings_and_stays_low() -> void:
	var darter: Alien = _spawn(DARTER, Vector3(12.0, 0.0, 0.0), true)
	var dive := darter.strain.attacks[0] as AlienDive
	var before: float = _player.health
	await _wait_until_winding_up(darter, 4.0)
	var lines: Array[Node] = _arena.get_children().filter(
		func(n: Node) -> bool: return n is ChargeLine
	)
	assert_eq(lines.size(), 1, "its line shows")
	assert_almost_eq((lines[0] as Node3D).global_position.y, 0.0, 0.05, "on the ground")
	await _wait_physics(dive.wind_up + 0.6)
	assert_almost_eq(_player.health, before - dive.damage, 0.01, "stung once")
	assert_lt(darter.global_position.y, 2.0, "low after the dive")
	await _wait_physics(dive.recovery + 1.5)
	assert_gt(darter.global_position.y, DARTER.flight_height - 0.6, "back up")


func test_a_dead_darter_drops_to_the_ground() -> void:
	var darter: Alien = _still(DARTER, Vector3(10.0, 0.0, 0.0))
	await _wait_physics(1.5)
	darter.take_damage(1000.0)
	await _wait_physics(0.6)
	assert_almost_eq(darter.global_position.y, 0.0, 0.05)


func test_a_stalker_far_away_is_hidden_and_close_shimmers() -> void:
	var stalker: Alien = _still(STALKER, Vector3(STALKER.cloak.reveal_range + 6.0, 0.0, 0.0))
	await _wait_physics(0.5)
	assert_true(stalker.cloaking.is_hidden())
	assert_false(PlayerAim.is_lockable(stalker), "can't be locked on")
	assert_true(stalker.is_hittable(), "but shots still hit it")
	stalker.global_position = Vector3(STALKER.cloak.reveal_range - 2.0, 0.0, 0.0)
	await _wait_physics(STALKER.cloak.fade_time + 0.1)
	assert_false(stalker.cloaking.is_hidden())
	assert_true(PlayerAim.is_lockable(stalker), "its shimmer can be locked on")
	assert_true(stalker.cloaking.is_cloaked(), "still see-through")


func test_a_hit_shows_a_stalker_for_a_while() -> void:
	var stalker: Alien = _still(STALKER, Vector3(STALKER.cloak.reveal_range + 6.0, 0.0, 0.0))
	await _wait_physics(0.5)
	stalker.take_hit(Hit.new(1.0, 0.0, 0.0, Vector3.RIGHT, stalker.get_aim_point(), _player))
	assert_true(PlayerAim.is_lockable(stalker), "right away")
	await _wait_physics(STALKER.cloak.fade_time + 0.1)
	assert_false(stalker.cloaking.is_cloaked(), "fully seen")
	await _wait_physics(STALKER.cloak.shown_time + STALKER.cloak.fade_time)
	assert_true(stalker.cloaking.is_hidden(), "hides again")


func test_the_stalker_backs_off_after_it_attacks() -> void:
	var stalker: Alien = _spawn(STALKER, Vector3(4.5, 0.0, 0.0), true)
	await _wait_until_winding_up(stalker, 2.0)
	assert_false(stalker.cloaking.is_hidden(), "shows when it attacks")
	while stalker.is_attacking():
		await wait_physics_frames(1)
	var after: float = stalker.horizontal_distance(_player)
	await _wait_physics(STALKER.retreat_time * 0.8)
	assert_gt(stalker.horizontal_distance(_player), after + 2.0, "backed off")


func test_the_stalker_stands_on_two_legs() -> void:
	var stalker: Alien = _spawn(STALKER, Vector3(30.0, 0.0, 0.0), false, Alien.Role.GUARD)
	await _wait_physics(1.0)
	var legs: AlienLegs = null
	for node: Node in stalker.find_children("*", "AlienLegs", true, false):
		legs = node as AlienLegs
	assert_eq(legs.feet.size(), 2)
	for foot: Vector3 in legs.feet.values():
		assert_almost_eq(foot.y, 0.0, 0.05, "on the ground")


func test_an_ambush_from_hiding_hits_hard() -> void:
	var stalker: Alien = _spawn(STALKER, Vector3(4.5, 0.0, 0.0), true)
	stalker.strain.attacks = [_attack_of(stalker, "AlienPounce")]
	var before: float = _player.health
	await _wait_until_winding_up(stalker, 2.0)
	assert_true(stalker.cloaking.ambush, "it attacks from hiding")
	await _wait_physics(1.0)
	assert_almost_eq(_player.health, before - STALKER.cloak.ambush_damage, 0.01)
	assert_false(stalker.cloaking.ambush, "only the first strike")


func test_the_hook_catches_and_slows() -> void:
	var stalker: Alien = _spawn(STALKER, Vector3(8.0, 0.0, 0.0), true)
	var hook := _attack_of(stalker, "AlienHook") as AlienHook
	stalker.strain.attacks = [hook]
	stalker.strain.move_speed = 0.0
	await wait_physics_frames(1)
	stalker.cloaking.reveal()
	var before: float = _player.health
	await _wait_until_winding_up(stalker, 2.0)
	await _wait_physics(hook.wind_up + 0.6)
	assert_almost_eq(_player.health, before - hook.damage, 0.01, "caught")
	assert_true(_player.ground_contact.is_snared())
	assert_almost_eq(_player.ground_contact.speed(), hook.snare, 0.001, "slowed, not pulled")
	assert_almost_eq(_player.global_position.x, 0.0, 0.05, "stays where it was")
	await _wait_physics(hook.snare_time + FleshHook.RETRACT_TIME + 0.1)
	assert_false(_player.ground_contact.is_snared())
	assert_eq(_arena.get_children().filter(func(n: Node) -> bool: return n is FleshHook).size(), 0)


func test_rock_stops_the_hook() -> void:
	_add_box(Vector3(1.0, 4.0, 6.0), Vector3(4.0, 2.0, 0.0))
	var stalker: Alien = _spawn(STALKER, Vector3(8.0, 0.0, 0.0), true)
	var hook := _attack_of(stalker, "AlienHook") as AlienHook
	stalker.strain.attacks = [hook]
	stalker.strain.move_speed = 0.0
	await wait_physics_frames(1)
	stalker.cloaking.reveal()
	var before: float = _player.health
	await _wait_until_winding_up(stalker, 2.0)
	await _wait_physics(hook.wind_up + 0.6)
	assert_eq(_player.health, before)
	assert_false(_player.ground_contact.is_snared())


func test_a_hiding_stalker_doesnt_hook() -> void:
	var stalker: Alien = _spawn(STALKER, Vector3(7.0, 0.0, 0.0), true)
	stalker.strain.attacks = [_attack_of(stalker, "AlienHook")]
	stalker.strain.move_speed = 0.0
	await _wait_physics(1.5)
	assert_false(stalker.is_attacking(), "from hiding it strikes instead")


func test_the_skimmer_circles_and_spits_on_the_move() -> void:
	var skimmer: Alien = _spawn(SKIMMER, Vector3(12.0, 0.0, 0.0), true)
	var spit := skimmer.strain.attacks[0] as AlienSpit
	var before: float = _player.health
	var start := Vector2(12.0, 0.0)
	var globs: int = 0
	var stood: int = 0
	for i: int in roundi(4.0 * Engine.physics_ticks_per_second):
		await wait_physics_frames(1)
		if _arena.get_children().any(func(n: Node) -> bool: return n is AcidGlob):
			globs += 1
		if Vector2(skimmer.velocity.x, skimmer.velocity.z).length() < 1.0:
			stood += 1
	var at := Vector2(skimmer.global_position.x, skimmer.global_position.z)
	assert_gt(rad_to_deg(absf(at.angle_to(start))), 30.0, "it circled")
	assert_between(at.length(), SKIMMER.keep_away - 1.5, spit.reach + 1.5, "at its range")
	assert_almost_eq(skimmer.global_position.y, SKIMMER.flight_height, 0.6)
	assert_gt(globs, 0, "it spat")
	assert_lt(_player.health, before, "and hit")
	assert_lt(stood, 15, "it never stopped")


func test_the_apex_comes_from_tier_3_more_often_farther_in() -> void:
	assert_eq(HIVE.apex, RAVAGER)
	assert_eq(HIVE.apex_chance_at(2), 0.0)
	assert_almost_eq(HIVE.apex_chance_at(3), HIVE.apex_chance, 0.001)
	assert_gt(HIVE.apex_chance_at(6), HIVE.apex_chance_at(3))
	assert_false(RAVAGER in HIVE.strains, "nests don't hatch it")


func test_the_ravager_roams_its_route() -> void:
	_player.global_position = Vector3(0.0, 0.0, 90.0)
	var ravager: Alien = RAVAGER.spawn(Alien.Role.GUARD)
	ravager.route = [Vector3(-40.0, 0.0, -40.0)]
	ravager.position = Vector3(10.0, 0.0, -40.0)
	_arena.add_child(ravager)
	await _wait_physics(3.0)
	assert_null(ravager.target, "the player is too far")
	assert_lt(ravager.global_position.x, 5.0, "on its way")


func test_the_ravager_sheds_swarmers() -> void:
	var ravager: Alien = _spawn(RAVAGER, Vector3(15.0, 0.0, 0.0), true)
	var shed: AlienShed = null
	for attack: AlienAttack in ravager.strain.attacks:
		if attack is AlienShed:
			shed = attack as AlienShed
	ravager.strain.attacks = [shed]
	ravager.strain.move_speed = 0.0
	await _wait_until_winding_up(ravager, 2.0)
	await _wait_physics(shed.wind_up + 0.1)
	var shed_aliens: Array[Node] = _arena.get_children().filter(
		func(n: Node) -> bool: return n is Alien and (n as Alien).strain == SWARMER
	)
	assert_eq(shed_aliens.size(), shed.count)
	for alien: Alien in shed_aliens:
		assert_eq(alien.role, Alien.Role.HUNTER)
		assert_almost_eq(alien.health_factor, ravager.health_factor, 0.001)


func test_the_ravagers_steps_throw_up_dust_and_shake_nearby() -> void:
	var ravager: Alien = RAVAGER.spawn(Alien.Role.GUARD)
	ravager.route = [Vector3(-40.0, 0.0, 0.0)]
	ravager.position = Vector3(10.0, 0.0, 30.0)
	_player.global_position = Vector3(0.0, 0.0, 90.0)
	_arena.add_child(ravager)
	await _wait_physics(2.0)
	var dust: Array[Node] = _arena.get_children().filter(
		func(n: Node) -> bool: return n is DustPuff
	)
	assert_gt(dust.size(), 0, "dust where it steps")
	assert_almost_eq(ravager.tremor.felt_at(ravager.global_position), 1.0, 0.001)
	var far: Vector3 = ravager.global_position + Vector3(AlienTremor.REACH + 1.0, 0.0, 0.0)
	assert_eq(ravager.tremor.felt_at(far), 0.0)


## The first attack of `alien` of the script class `kind`.
func _attack_of(alien: Alien, kind: String) -> AlienAttack:
	for attack: AlienAttack in alien.strain.attacks:
		if (attack.get_script() as Script).get_global_name() == kind:
			return attack
	return null


func _add_box(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	_arena.add_child(body)


func _spawn(
	strain: AlienStrain, at: Vector3, own: bool = false, role: Alien.Role = Alien.Role.HUNTER
) -> Alien:
	var alien: Alien = strain.spawn(role)
	if own:
		alien.strain = strain.duplicate() as AlienStrain
	alien.position = at
	_arena.add_child(alien)
	return alien


## An alien that neither moves nor attacks.
func _still(strain: AlienStrain, at: Vector3) -> Alien:
	var alien: Alien = _spawn(strain, at, true)
	alien.strain.move_speed = 0.0
	alien.strain.attacks = []
	return alien


func _wait_until_winding_up(alien: Alien, seconds: float) -> void:
	for i: int in roundi(seconds * Engine.physics_ticks_per_second):
		if alien.is_winding_up():
			return
		await wait_physics_frames(1)
	fail_test("never wound up")


func _wait_physics(seconds: float) -> void:
	await wait_physics_frames(roundi(seconds * Engine.physics_ticks_per_second))
