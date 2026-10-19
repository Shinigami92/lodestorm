extends GutTest
## The tier 1 and 2 strains besides the swarmer: the mite, the spitter (keeping away, its acid) and
## the burrower (under the ground, its bite from below).

const MITE: AlienStrain = preload("res://game/aliens/strains/mite/mite.tres")
const SPITTER: AlienStrain = preload("res://game/aliens/strains/spitter/spitter.tres")
const BURROWER: AlienStrain = preload("res://game/aliens/strains/burrower/burrower.tres")
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


func test_a_mite_dies_from_one_hit() -> void:
	var mite: Alien = _spawn(MITE, Vector3(30.0, 0.0, 0.0))
	await wait_physics_frames(1)
	mite.take_hit(Hit.new(10.0, 7.0, 0.5, Vector3.LEFT, mite.get_aim_point(), _player))
	assert_true(mite.dead)
	assert_lt(MITE.cap_share, 1.0, "counts as a share towards the cap")


func test_six_legs_step_in_tripods() -> void:
	var mite: Alien = _spawn(MITE, Vector3(30.0, 0.0, 0.0))
	await _wait_physics(0.6)
	var legs: AlienLegs = null
	for node: Node in mite.find_children("*", "AlienLegs", true, false):
		legs = node as AlienLegs
	assert_not_null(legs)
	assert_eq(legs.feet.size(), 6)
	for foot: Vector3 in legs.feet.values():
		assert_almost_eq(foot.y, 0.0, 0.05, "on the ground")


func test_mites_bite_players_in_reach() -> void:
	var mite: Alien = _spawn(MITE, Vector3(0.6, 0.0, 0.0))
	var before: float = _player.health
	await _wait_physics(0.3)
	assert_eq(mite.target, _player)
	assert_lt(_player.health, before)


func test_the_spitter_backs_away_from_a_close_player() -> void:
	var spitter: Alien = _spawn(SPITTER, Vector3(5.0, 0.0, 0.0), true)
	# No spitting, only keeping away.
	spitter.strain.attacks = []
	await _wait_physics(1.5)
	assert_gt(spitter.horizontal_distance(_player), 8.0)


func test_the_spitter_comes_closer_from_far_away() -> void:
	var spitter: Alien = _spawn(SPITTER, Vector3(18.0, 0.0, 0.0), true)
	spitter.strain.attacks = []
	await _wait_physics(1.5)
	var distance: float = spitter.horizontal_distance(_player)
	assert_lt(distance, 17.0)
	assert_gt(distance, SPITTER.keep_away - 1.0, "keeps its distance")


func test_spit_lands_where_the_player_stood_and_burns() -> void:
	var spitter: Alien = _spawn(SPITTER, Vector3(10.0, 0.0, 0.0), true)
	watch_signals(spitter)
	var spit := spitter.strain.attacks[0] as AlienSpit
	var before: float = _player.health
	await _wait_physics(spit.wind_up + 0.2)
	var globs: Array[Node] = _arena.get_children().filter(
		func(n: Node) -> bool: return n is AcidGlob
	)
	assert_eq(globs.size(), 1, "it spat")
	var glob := globs[0] as AcidGlob
	assert_almost_eq(glob.landing.distance_to(_player.global_position), 0.0, 0.3)
	var ring := glob.get_node("Ring") as Node3D
	assert_almost_eq(ring.global_position.x, _player.global_position.x, 0.1, "ring where it lands")
	await _wait_physics(glob.flight_time + 0.1)
	assert_lt(_player.health, before, "splashed")
	var puddles: Array[Node] = _arena.get_children().filter(
		func(n: Node) -> bool: return n is AcidPuddle
	)
	assert_eq(puddles.size(), 1, "a puddle stays")


func test_the_puddle_hurts_players_not_aliens() -> void:
	var mite: Alien = _spawn(MITE, Vector3(0.5, 0.0, 0.5), true)
	mite.strain.attacks = []
	mite.strain.move_speed = 0.0
	var puddle: AcidPuddle = AcidPuddle.spawn(_arena, _player.global_position, 1.5, 2.0, 10.0)
	var before: float = _player.health
	await _wait_physics(1.1)
	assert_true(puddle.covers(mite))
	assert_almost_eq(_player.health, before - 10.0, 0.01)
	assert_eq(mite.health, mite.max_health(), "the hive's own acid")
	await _wait_physics(1.2)
	assert_false(is_instance_valid(puddle), "dries up")


func test_a_burrower_underground_cant_be_hit() -> void:
	var burrower: Alien = _spawn(BURROWER, Vector3(20.0, 0.0, 0.0), true)
	burrower.strain.surface_time = 0.0
	await _wait_physics(0.2)
	assert_true(burrower.underground, "digs in for a target far away")
	assert_false(burrower.is_hittable())
	assert_false(PlayerAim.is_lockable(burrower))
	assert_eq(burrower.take_hit(Hit.new(50.0, 0.0, 0.0, Vector3.LEFT, Vector3.ZERO, _player)), 0.0)
	assert_eq(burrower.health, burrower.max_health())
	await _wait_physics(0.6)
	var ripple := burrower.get_children().filter(func(n: Node) -> bool: return n is BurrowRipple)
	assert_eq(ripple.size(), 1)
	assert_true((ripple[0] as BurrowRipple).active, "only a ripple shows")


func test_a_burrower_bursts_up_under_a_player_standing_still() -> void:
	var burrower: Alien = _spawn(BURROWER, Vector3(8.0, 0.0, 0.0), true)
	burrower.strain.surface_time = 0.0
	var eruption := burrower.strain.attacks[0] as AlienEruption
	var before: float = _player.health
	await _wait_until_winding_up(burrower, 5.0)
	assert_true(burrower.underground, "the ground bulges first")
	await _wait_physics(eruption.wind_up + 0.1)
	assert_false(burrower.underground, "it came up")
	assert_true(burrower.is_hittable())
	assert_almost_eq(_player.health, before - eruption.damage, 0.01)


func test_moving_away_during_the_bulge_dodges_the_bite() -> void:
	var burrower: Alien = _spawn(BURROWER, Vector3(8.0, 0.0, 0.0), true)
	burrower.strain.surface_time = 0.0
	var eruption := burrower.strain.attacks[0] as AlienEruption
	var before: float = _player.health
	await _wait_until_winding_up(burrower, 5.0)
	_player.global_position += Vector3(0.0, 0.0, 3.0)
	await _wait_physics(eruption.wind_up + 0.1)
	assert_false(burrower.underground)
	assert_eq(_player.health, before)


## An alien of `strain` at `at`; `own` gives it its own copy of the strain to change.
func _spawn(strain: AlienStrain, at: Vector3, own: bool = false) -> Alien:
	var alien: Alien = strain.spawn(Alien.Role.HUNTER)
	if own:
		alien.strain = strain.duplicate() as AlienStrain
	alien.position = at
	_arena.add_child(alien)
	return alien


func _wait_until_winding_up(alien: Alien, seconds: float) -> void:
	for i: int in roundi(seconds * Engine.physics_ticks_per_second):
		if alien.is_winding_up():
			return
		await wait_physics_frames(1)
	fail_test("never wound up")


func _wait_physics(seconds: float) -> void:
	await wait_physics_frames(roundi(seconds * Engine.physics_ticks_per_second))
