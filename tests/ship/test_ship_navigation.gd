extends GutTest
## Where the crew can walk aboard (`ShipNavigation`): baked once it's first asked for a way, on its
## own navigation map, through the doors and around the walls and stations, only on the floors.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")

var _map: Node3D
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func test_baked_when_first_asked_on_its_own_map() -> void:
	var navigation: ShipNavigation = _ship.navigation
	assert_false(navigation.is_baked(), "nothing baked before anyone walks")
	var bridge: Vector3 = _ship.to_global(Vector3(-63.0, 7.0, -2.0))
	var cockpit: Vector3 = _ship.to_global(Vector3(-96.0, 7.0, 0.0))
	assert_eq(navigation.find_path(bridge, cockpit).size(), 0, "no way until it's baked")
	await _baked(navigation)
	assert_ne(navigation.map, _ship.get_world_3d().navigation_map, "not the aliens' map")
	var path: PackedVector3Array = navigation.find_path(bridge, cockpit)
	assert_gt(path.size(), 1, "from the bridge into the cockpit")
	var door: Vector3 = _ship.to_global(Vector3(-80.75, 7.0, 0.0))
	assert_lt(_distance_to(path, door), 1.5, "through the cockpit's door")


func test_walls_and_stations_are_kept_clear() -> void:
	var navigation: ShipNavigation = _ship.navigation
	navigation.bake()
	await _baked(navigation)
	var wall: Vector3 = _ship.to_global(Vector3(-16.0, 2.5, -2.75))
	assert_gt(navigation.closest_point(wall).distance_to(wall), 0.3, "not inside the armory's wall")
	var door: Vector3 = _ship.to_global(Vector3(-12.5, 2.5, -2.75))
	assert_lt(navigation.closest_point(door).distance_to(door), 0.25, "but through its door")
	var table: Vector3 = (_ship.get_node("Rooms/Upper/Bridge/HoloTable") as Node3D).global_position
	var beside: Vector3 = navigation.closest_point(table + _ship.global_basis.x * 2.0)
	assert_gt(
		Vector2(beside.x - table.x, beside.z - table.z).length(), 2.4, "around the holo table"
	)
	var top: Vector3 = navigation.closest_point(table + _ship.global_basis.y * 0.9)
	assert_almost_eq(top.y, table.y + 0.2, 0.15, "on the floor, never on the table's top")


func _baked(navigation: ShipNavigation) -> void:
	for i: int in 300:
		if navigation.is_baked():
			break
		await wait_physics_frames(1)
	assert_true(navigation.is_baked(), "baked")
	await wait_physics_frames(2)


func _distance_to(path: PackedVector3Array, point: Vector3) -> float:
	var nearest: float = INF
	for i: int in range(1, path.size()):
		var on: Vector3 = Geometry3D.get_closest_point_to_segment(point, path[i - 1], path[i])
		nearest = minf(nearest, on.distance_to(point))
	return nearest
