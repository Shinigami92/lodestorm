extends GutTest
## Nests hatch one alien at a time (see `AlienNest`): a pack one after another, the hive at most
## one per physics frame.

const NEST_SCENE: PackedScene = preload("res://game/aliens/nest/alien_nest.tscn")
const TEST_MAP := preload("res://tests/support/test_map.gd")
const SWARMER: AlienStrain = preload("res://game/aliens/strains/swarmer/swarmer.tres")

var _map: Node3D
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_ship = _map.get_node("Ship") as Ship
	# The location's own nests would get in the way.
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		nest.queue_free()
	await wait_physics_frames(2)


func test_a_pack_hatches_one_alien_after_another() -> void:
	var nest: AlienNest = _add_nest(Vector3(55.0, 0.0, 0.0), 3)
	await wait_physics_frames(1)
	var cap: float = nest.settings.alien_cap()
	assert_eq(nest.hatch_pack().size(), 3, "the whole pack")
	assert_eq(nest.get_hunters().size(), 1, "the first one right away")
	assert_almost_eq(AlienNest.waiting_load(get_tree()), 2.0, 1e-4, "the others wait")
	assert_true(nest.is_full(cap - Alien.living_load(get_tree()) - 1.5), "and count to the cap")
	await _wait_physics(nest.settings.hatch_gap + 0.05)
	assert_eq(nest.get_hunters().size(), 2, "the next one a gap later")
	await _wait_physics(nest.settings.hatch_gap)
	assert_eq(nest.get_hunters().size(), 3)


func test_the_hive_hatches_one_alien_per_frame() -> void:
	var one: AlienNest = _add_nest(Vector3(55.0, 0.0, 0.0), 1)
	var other: AlienNest = _add_nest(Vector3(-55.0, 0.0, 0.0), 1)
	await wait_physics_frames(1)
	one.hatch_pack()
	other.hatch_pack()
	assert_eq(one.get_hunters().size() + other.get_hunters().size(), 1, "one this frame")
	await wait_physics_frames(1)
	assert_eq(one.get_hunters().size() + other.get_hunters().size(), 2, "the other one next")


## A nest without guards whose packs are `size` swarmers.
func _add_nest(offset: Vector3, size: int) -> AlienNest:
	var nest := NEST_SCENE.instantiate() as AlienNest
	nest.settings = nest.settings.duplicate() as AlienNestSettings
	nest.settings.guards = 0
	var pack := AlienPack.new()
	pack.members = {SWARMER: size}
	var hive := AlienHive.new()
	hive.strains = [SWARMER]
	hive.packs = [pack]
	nest.table = hive.table(1)
	nest.position = _ship.to_global(offset)
	_map.add_child(nest)
	return nest


func _wait_physics(seconds: float) -> void:
	await wait_physics_frames(roundi(seconds * Engine.physics_ticks_per_second))
