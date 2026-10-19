extends GutTest
## The tier 3 and 4 strains: the brute (its plates, its charge), the shrieker (its scream), the
## bloater (its burst and the acid cloud) and the tender (its links).

const BRUTE: AlienStrain = preload("res://game/aliens/strains/brute/brute.tres")
const SHRIEKER: AlienStrain = preload("res://game/aliens/strains/shrieker/shrieker.tres")
const BLOATER: AlienStrain = preload("res://game/aliens/strains/bloater/bloater.tres")
const TENDER: AlienStrain = preload("res://game/aliens/strains/tender/tender.tres")
const MITE: AlienStrain = preload("res://game/aliens/strains/mite/mite.tres")
const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")
const MINER_SCENE: PackedScene = preload("res://game/mining/miner.tscn")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")

var _arena: Node3D
var _player: Player


func before_each() -> void:
	_arena = Node3D.new()
	add_child_autofree(_arena)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	_arena.add_child(floor_body)
	_player = PLAYER_SCENE.instantiate() as Player
	_arena.add_child(_player)
	await wait_physics_frames(1)


func test_the_brutes_plates_hold_and_its_back_doesnt() -> void:
	var brute: Alien = _spawn(BRUTE, Vector3(30.0, 0.0, 0.0))
	await wait_physics_frames(1)
	var forward: Vector3 = -brute.global_basis.z
	var front: float = brute.take_hit(_hit(10.0, 40.0, -forward, brute))
	assert_almost_eq(front, maxf(10.0 - BRUTE.armor, 10.0 * Alien.MIN_DAMAGE_SHARE), 0.01)
	assert_almost_eq(brute.stagger, 40.0 * BRUTE.armored_stagger, 0.5, "the plates hold")
	var back: float = brute.take_hit(_hit(10.0, 40.0, forward, brute))
	assert_almost_eq(back, 10.0, 0.01, "its back is soft")
	brute.take_hit(_hit(10.0, 40.0, forward, brute))
	assert_true(brute.is_staggered(), "two heavy hits from behind stagger it")


func test_the_charge_shows_its_line_then_runs_through() -> void:
	var brute: Alien = _spawn(BRUTE, Vector3(10.0, 0.0, 0.0), true)
	brute.strain.attacks = [brute.strain.attacks[0]]
	var charge := brute.strain.attacks[0] as AlienCharge
	var before: float = _player.health
	await _wait_until_winding_up(brute, 2.0)
	var lines: Array[Node] = _arena.get_children().filter(
		func(n: Node) -> bool: return n is ChargeLine
	)
	assert_eq(lines.size(), 1, "its line shows on the ground")
	var line := lines[0] as ChargeLine
	assert_almost_eq(line.length, 10.0 + charge.overshoot, 0.5, "past where the player stands")
	await _wait_physics(charge.wind_up + 1.2)
	assert_almost_eq(_player.health, before - charge.damage, 0.01, "hit once")
	assert_lt(brute.global_position.x, 0.0, "ran through")
	assert_false(is_instance_valid(line), "the line is gone")


func test_stepping_out_of_the_line_dodges_the_charge() -> void:
	var brute: Alien = _spawn(BRUTE, Vector3(10.0, 0.0, 0.0), true)
	brute.strain.attacks = [brute.strain.attacks[0]]
	var charge := brute.strain.attacks[0] as AlienCharge
	var before: float = _player.health
	await _wait_until_winding_up(brute, 2.0)
	_player.global_position = Vector3(5.0, 0.0, 4.0)
	await _wait_physics(charge.wind_up + 1.2)
	assert_eq(_player.health, before)


func test_a_charge_into_rock_dazes_it() -> void:
	var rock := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 3.0, 6.0)
	shape.shape = box
	rock.add_child(shape)
	rock.position = Vector3(4.0, 1.5, 0.0)
	_arena.add_child(rock)
	var brute: Alien = _spawn(BRUTE, Vector3(11.0, 0.0, 0.0), true)
	brute.strain.attacks = [brute.strain.attacks[0]]
	var charge := brute.strain.attacks[0] as AlienCharge
	await _wait_until_winding_up(brute, 2.0)
	await _wait_physics(charge.wind_up + 0.6)
	assert_true(brute.is_staggered(), "dazed, its back open")
	assert_gt(brute.global_position.x, 4.0, "stopped at the rock")


func test_the_scream_speeds_up_aliens_near_it() -> void:
	var shrieker: Alien = _spawn(SHRIEKER, Vector3(18.0, 0.0, 0.0), true)
	shrieker.strain.move_speed = 0.0
	var scream := shrieker.strain.attacks[0] as AlienScream
	var near: Alien = _still(MITE, Vector3(18.0, 0.0, 6.0))
	var far: Alien = _still(MITE, Vector3(18.0, 0.0, -scream.radius - 5.0))
	watch_signals(shrieker)
	await _wait_until_winding_up(shrieker, 1.0)
	await _wait_physics(scream.wind_up + 0.1)
	assert_true(near.status.is_boosted())
	assert_almost_eq(near.status.speed(), scream.boost, 0.001)
	assert_true(shrieker.status.is_boosted(), "itself too")
	assert_false(far.status.is_boosted(), "out of its reach")
	assert_signal_emitted(shrieker, "called_for_help")
	await _wait_physics(scream.boost_time)
	assert_false(near.status.is_boosted(), "wears off")


func test_focus_fire_breaks_off_the_scream() -> void:
	var shrieker: Alien = _spawn(SHRIEKER, Vector3(18.0, 0.0, 0.0), true)
	shrieker.strain.move_speed = 0.0
	var scream := shrieker.strain.attacks[0] as AlienScream
	watch_signals(shrieker)
	await _wait_until_winding_up(shrieker, 1.0)
	for i: int in 3:
		shrieker.take_hit(_hit(1.0, 7.0, Vector3.RIGHT, shrieker))
	assert_true(shrieker.is_staggered())
	await _wait_physics(scream.wind_up)
	assert_signal_not_emitted(shrieker, "called_for_help")
	assert_false(shrieker.status.is_boosted())


func test_the_shrieker_stays_back() -> void:
	var shrieker: Alien = _spawn(SHRIEKER, Vector3(6.0, 0.0, 0.0), true)
	shrieker.strain.attacks = []
	await _wait_physics(1.5)
	assert_gt(shrieker.horizontal_distance(_player), 9.0)


func test_the_bloater_bursts_next_to_a_player_not_a_miner() -> void:
	var miner := MINER_SCENE.instantiate() as Miner
	miner.position = Vector3(6.0, 0.0, 6.0)
	_arena.add_child(miner)
	var bloater: Alien = _spawn(BLOATER, Vector3(12.0, 0.0, 6.0))
	var burst := bloater.strain.attacks[0] as AlienBurst
	var before: float = _player.health
	await wait_physics_frames(2)
	assert_eq(bloater.target, _player, "it hunts players, not miners")
	await _wait_until_winding_up(bloater, 6.0)
	assert_lt(bloater.horizontal_distance(_player), bloater.horizontal_distance(miner))
	await _wait_physics(burst.wind_up + 0.1)
	assert_true(bloater.dead, "it burst")
	assert_lt(_player.health, before)
	assert_eq(_clouds().size(), 1, "an acid cloud stays")


func test_killing_a_bloater_bursts_it_and_hurts_aliens_too() -> void:
	var bloater: Alien = _spawn(BLOATER, Vector3(20.0, 0.0, 0.0), true)
	bloater.strain.move_speed = 0.0
	var mite: Alien = _still(MITE, Vector3(21.5, 0.0, 0.0))
	var swarmer: Alien = _still(SWARMER, Vector3(20.0, 0.0, 2.0))
	await wait_physics_frames(1)
	bloater.take_hit(_hit(1000.0, 0.0, Vector3.RIGHT, bloater))
	await wait_physics_frames(2)
	assert_eq(_clouds().size(), 1, "it burst")
	assert_true(mite.dead, "the splash")
	var after_splash: float = swarmer.health
	assert_lt(after_splash, swarmer.max_health())
	await _wait_physics(1.1)
	assert_lt(swarmer.health, after_splash, "the cloud burns aliens")


func test_the_tender_links_the_most_hurt_and_mends_them() -> void:
	var tender: Alien = _still(TENDER, Vector3(20.0, 0.0, 0.0))
	var mend: AlienMend = TENDER.mend
	var aliens: Array[Alien] = []
	for i: int in 4:
		aliens.append(_still(SWARMER, Vector3(22.0 + i, 0.0, 3.0)))
	aliens[3].health = 10.0
	aliens[2].health = 15.0
	await _wait_physics(0.6)
	var links: MendLinks = _links(tender)
	assert_eq(links.linked.count(null), 0, "all of its links in use")
	assert_true(aliens[3] in links.linked, "the most hurt first")
	assert_true(aliens[2] in links.linked)
	assert_eq(aliens[3].status.bonus_armor, mend.armor, "hardened")
	var unlinked: Alien = aliens.filter(func(a: Alien) -> bool: return a not in links.linked)[0]
	assert_eq(unlinked.status.bonus_armor, 0.0)
	var dealt: float = aliens[3].take_hit(_hit(10.0, 0.0, Vector3.RIGHT, aliens[3]))
	assert_almost_eq(dealt, 10.0 - mend.armor, 0.01)
	var hurt: float = aliens[3].health
	await _wait_physics(1.0)
	assert_almost_eq(aliens[3].health, hurt + mend.heal_per_second, 0.5, "heals")


func test_links_break_with_distance_and_death() -> void:
	var tender: Alien = _still(TENDER, Vector3(20.0, 0.0, 0.0))
	var other_tender: Alien = _still(TENDER, Vector3(22.0, 0.0, 0.0))
	var swarmer: Alien = _still(SWARMER, Vector3(20.0, 0.0, 3.0))
	var mite: Alien = _still(MITE, Vector3(18.0, 0.0, 3.0))
	await _wait_physics(0.6)
	var links: MendLinks = _links(tender)
	assert_false(other_tender in links.linked, "tenders don't link each other")
	assert_false(other_tender in _links(other_tender).linked)
	var linked: Array[Alien] = []
	linked.assign(links.linked.filter(func(a: Alien) -> bool: return a != null))
	linked.append_array(
		_links(other_tender).linked.filter(func(a: Alien) -> bool: return a != null)
	)
	assert_eq(linked.size(), 2, "one link per alien")
	assert_true(swarmer in linked and mite in linked)
	var mine: Alien = links.linked.filter(func(a: Alien) -> bool: return a != null)[0]
	mine.global_position = Vector3(20.0, 0.0, TENDER.mend.break_range + 3.0)
	await wait_physics_frames(2)
	assert_false(mine in links.linked, "too far")
	assert_eq(mine.status.bonus_armor, 0.0)
	tender.take_damage(1000.0)
	other_tender.take_damage(1000.0)
	await wait_physics_frames(2)
	for alien: Alien in [swarmer, mite]:
		assert_false(alien.status.is_mended())
		assert_eq(alien.status.bonus_armor, 0.0)


func test_the_new_bodies_stand_on_their_legs() -> void:
	var legs_of: Dictionary[AlienStrain, int] = {BRUTE: 4, SHRIEKER: 4, BLOATER: 6, TENDER: 6}
	var aliens: Dictionary[AlienStrain, Alien] = {}
	var x: float = 15.0
	for strain: AlienStrain in legs_of:
		aliens[strain] = _still(strain, Vector3(x, 0.0, 20.0))
		x += 5.0
	await _wait_physics(0.6)
	for strain: AlienStrain in legs_of:
		var legs: AlienLegs = null
		for node: Node in aliens[strain].find_children("*", "AlienLegs", true, false):
			legs = node as AlienLegs
		assert_eq(legs.feet.size(), legs_of[strain], strain.display_name)
		for foot: Vector3 in legs.feet.values():
			assert_almost_eq(foot.y, 0.0, 0.05, "%s on the ground" % strain.display_name)


func test_a_link_to_an_alien_freed_without_dying_is_taken_again() -> void:
	var tender: Alien = _still(TENDER, Vector3(20.0, 0.0, 0.0))
	var aliens: Array[Alien] = []
	for i: int in 4:
		aliens.append(_still(SWARMER, Vector3(22.0 + i, 0.0, 3.0)))
	await _wait_physics(0.6)
	var links: MendLinks = _links(tender)
	var gone: Alien = links.linked[0]
	var spare: Alien = aliens.filter(func(a: Alien) -> bool: return a not in links.linked)[0]
	gone.free()
	await _wait_physics(1.0)
	assert_true(spare in links.linked, "the free slot links the next one")


func test_boosted_and_mended_aliens_grow_and_shrink_back() -> void:
	var swarmer: Alien = _still(SWARMER, Vector3(20.0, 0.0, 0.0))
	await wait_physics_frames(1)
	var model := swarmer.get_node("Body/Model") as Node3D
	assert_almost_eq(model.scale.x, 1.0, 0.001)
	swarmer.status.boost(1.25, 1.0)
	await _wait_physics(0.6)
	assert_almost_eq(model.scale.x, Alien.BUFFED_SCALE, 0.02, "a little bigger while boosted")
	await _wait_physics(1.2)
	assert_almost_eq(model.scale.x, 1.0, 0.02, "back to its size")
	var tender: Alien = _still(TENDER, Vector3(22.0, 0.0, 0.0))
	await _wait_physics(1.0)
	assert_true(swarmer.status.is_mended())
	assert_almost_eq(model.scale.x, Alien.BUFFED_SCALE, 0.02, "and while mended")
	tender.take_damage(1000.0)
	await _wait_physics(1.0)
	assert_almost_eq(model.scale.x, 1.0, 0.02)


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
func _still(strain: AlienStrain, at: Vector3, role: Alien.Role = Alien.Role.HUNTER) -> Alien:
	var alien: Alien = _spawn(strain, at, true, role)
	alien.strain.move_speed = 0.0
	alien.strain.attacks = []
	return alien


func _hit(damage: float, stagger: float, direction: Vector3, alien: Alien) -> Hit:
	return Hit.new(damage, stagger, 0.0, direction, alien.get_aim_point(), _player)


func _links(alien: Alien) -> MendLinks:
	for child: Node in alien.get_children():
		if child is MendLinks:
			return child as MendLinks
	return null


func _clouds() -> Array[Node]:
	return _arena.get_children().filter(func(n: Node) -> bool: return n is AcidCloud)


func _wait_until_winding_up(alien: Alien, seconds: float) -> void:
	for i: int in roundi(seconds * Engine.physics_ticks_per_second):
		if alien.is_winding_up():
			return
		await wait_physics_frames(1)
	fail_test("never wound up")


func _wait_physics(seconds: float) -> void:
	await wait_physics_frames(roundi(seconds * Engine.physics_ticks_per_second))
