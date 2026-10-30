extends GutTest
## A hunt's brood nest (see `AlienNest.brood`): it sleeps until a player comes close, then hatches
## only its strain, in packs, until the hunt's kills are out; its bursts are of its strain too.
## Every look of it is a brood nest.

const BROOD_NESTS: Array[PackedScene] = [
	preload("res://game/aliens/nest/brood_clutch.tscn"),
	preload("res://game/aliens/nest/brood_cocoons.tscn"),
	preload("res://game/aliens/nest/brood_pit.tscn"),
]
const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const SPITTER: AlienStrain = preload("res://game/aliens/strains/spitter/spitter.tres")
const MITE: AlienStrain = preload("res://game/aliens/strains/mite/mite.tres")

var _map: Node3D
var _mission: Mission
var _player: Player
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_mission = _map.get_node("Mission") as Mission
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	# The location's own nests would get in the way.
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		nest.queue_free()
	await wait_physics_frames(2)


func test_every_look_is_a_brood_nest() -> void:
	for scene: PackedScene in BROOD_NESTS:
		var nest := scene.instantiate() as AlienNest
		assert_eq(nest.kind, AlienNest.Kind.BROOD, scene.resource_path)
		assert_eq(nest.settings.guards, 0, "no guards: it is the fight")
		assert_gt(nest.settings.wake_range, 0.0, "it sleeps until a player comes close")
		nest.free()


func test_it_sleeps_until_a_player_comes_close() -> void:
	var nest: AlienNest = _add_nest(SPITTER, 5, Vector3(80.0, 0.0, 0.0), true)
	await _start_mission()
	assert_false(nest.is_awake(), "the player is far away")
	assert_eq(nest.hatch_pack().size(), 0, "nothing while it sleeps")
	_player.global_position = nest.global_position + Vector3(nest.settings.wake_range - 2.0, 0, 0)
	_player.reset_physics_interpolation()
	await wait_physics_frames(3)
	assert_true(nest.is_awake())
	assert_gt(nest.get_hunters().size(), 0, "its first pack right away")


func test_its_packs_are_its_strain_until_the_kills_are_out() -> void:
	var nest: AlienNest = _add_nest(SPITTER, 3, Vector3(30.0, 0.0, 0.0))
	await _start_mission()
	nest.brood_left = 3
	var first: Array[AlienStrain] = nest.hatch_pack()
	var size: int = maxi(floori(nest.settings.brood_pack / SPITTER.cap_share), 1)
	assert_eq(first.size(), mini(size, 3))
	for strain: AlienStrain in first:
		assert_eq(strain, SPITTER)
	for i: int in 3:
		if nest.brood_left > 0:
			assert_false(nest.hatch_pack().is_empty())
	assert_eq(nest.brood_left, 0)
	assert_eq(nest.hatch_pack().size(), 0, "no more than the hunt needs")


func test_small_strains_come_in_bigger_packs() -> void:
	var nest: AlienNest = _add_nest(MITE, -1, Vector3(30.0, 0.0, 0.0))
	await _start_mission()
	assert_eq(nest.hatch_pack().size(), floori(nest.settings.brood_pack / MITE.cap_share))


func test_its_bursts_are_its_strain() -> void:
	var nest: AlienNest = _add_nest(SPITTER, 0, Vector3(30.0, 0.0, 0.0))
	await _start_mission()
	var before: int = nest.get_hunters().size()
	nest.body.take_damage(nest.body.max_health * 0.4)
	await _wait_physics(nest.settings.burst_warning + nest.settings.hatch_gap * 4.0 + 0.2)
	var hunters: Array[Alien] = nest.get_hunters()
	assert_gt(hunters.size(), before, "a burst, though its packs are done")
	for alien: Alien in hunters:
		assert_eq(alien.strain, SPITTER)


## The egg clutch hunting `strain` with `left` kills to hatch, at `offset` from the ship; unless
## `sleeping`, awake from the start.
func _add_nest(
	strain: AlienStrain, left: int, offset: Vector3, sleeping: bool = false
) -> AlienNest:
	var nest := BROOD_NESTS[0].instantiate() as AlienNest
	if not sleeping:
		nest.settings = nest.settings.duplicate() as AlienNestSettings
		nest.settings.wake_range = 0.0
	nest.brood = strain
	nest.brood_left = left
	nest.position = _ship.to_global(offset)
	_map.add_child(nest)
	return nest


func _start_mission() -> void:
	_mission.state = Mission.State.OPEN
	_player.global_position = _ship.to_global(Vector3(22.0, 0.0, -40.0))
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)
	assert_eq(_mission.state, Mission.State.RUNNING)


func _wait_physics(seconds: float) -> void:
	await wait_physics_frames(ceili(seconds * Engine.physics_ticks_per_second))
