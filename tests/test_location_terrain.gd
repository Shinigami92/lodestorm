extends GutTest


## A 4×4 grid, 2 m apart, starting at (-4, -4), rising 1 m per grid step along x.
func _ramp() -> LocationTerrain:
	var terrain := LocationTerrain.new(Vector2(-4.0, -4.0), 4, 2.0)
	for z: int in 5:
		for x: int in 5:
			terrain.set_height(x, z, float(x))
	return terrain


func test_height_between_grid_points() -> void:
	var terrain: LocationTerrain = _ramp()
	assert_almost_eq(terrain.height_at(-4.0, -4.0), 0.0, 0.001)
	assert_almost_eq(terrain.height_at(-3.0, -2.5), 0.5, 0.001)
	assert_almost_eq(terrain.height_at(1.0, 3.0), 2.5, 0.001)
	# Outside, it's the height at the edge.
	assert_almost_eq(terrain.height_at(10.0, 0.0), 4.0, 0.001)


func test_height_follows_the_triangles() -> void:
	var terrain := LocationTerrain.new(Vector2.ZERO, 1, 1.0)
	terrain.set_height(1, 1, 1.0)
	# Only the far corner is raised: the near triangle stays flat.
	assert_almost_eq(terrain.height_at(0.4, 0.4), 0.0, 0.001)
	assert_almost_eq(terrain.height_at(0.75, 0.75), 0.5, 0.001)


func test_slope() -> void:
	var terrain: LocationTerrain = _ramp()
	assert_almost_eq(terrain.slope(2, 2), 0.5, 0.001)


func test_highest_around() -> void:
	var terrain: LocationTerrain = _ramp()
	terrain.set_height(0, 4, 9.0)
	var highest: PackedFloat32Array = terrain.highest_around(1)
	# One step towards +x is the highest, at the edge the grid ends.
	assert_almost_eq(highest[terrain.index(1, 1)], 2.0, 0.001)
	assert_almost_eq(highest[terrain.index(4, 0)], 4.0, 0.001)
	# The raised corner reaches its neighbors (diagonal too), not farther.
	assert_almost_eq(highest[terrain.index(1, 3)], 9.0, 0.001)
	assert_almost_eq(highest[terrain.index(2, 2)], 3.0, 0.001)


func test_flatten() -> void:
	var terrain: LocationTerrain = _ramp()
	terrain.flatten(Vector2.ZERO, 2.0, 2.0, 10.0)
	assert_almost_eq(terrain.height_at(0.0, 0.0), 10.0, 0.001)
	assert_almost_eq(terrain.height_at(2.0, 0.0), 10.0, 0.001)
	# Beyond radius and falloff, the ground stays as it was.
	assert_almost_eq(terrain.height_at(-4.0, -4.0), 0.0, 0.001)


func test_reachable_stops_at_cliffs() -> void:
	var terrain: LocationTerrain = _ramp()
	for z: int in 5:
		terrain.set_height(3, z, 20.0)
	var reached: PackedByteArray = terrain.reachable_from(Vector2(-4.0, 0.0), 1.0)
	assert_eq(reached[terrain.index(2, 2)], 1)
	assert_eq(reached[terrain.index(3, 2)], 0, "the cliff")
	assert_eq(reached[terrain.index(4, 2)], 0, "behind the cliff")


func test_mesh_and_shape_cover_the_grid() -> void:
	var terrain: LocationTerrain = _ramp()
	var mesh: ArrayMesh = terrain.build_mesh(
		Vector2i.ZERO, Vector2i(2, 2), func(_p: Vector3, _n: Vector3) -> Color: return Color.WHITE
	)
	var aabb: AABB = mesh.get_aabb()
	assert_almost_eq(aabb.position, Vector3(-4.0, 0.0, -4.0), Vector3.ONE * 0.001)
	assert_almost_eq(aabb.end, Vector3(0.0, 2.0, 0.0), Vector3.ONE * 0.001)
	assert_eq(terrain.build_shape(Vector2i.ZERO, Vector2i(2, 2)).get_faces().size(), 2 * 2 * 6)
