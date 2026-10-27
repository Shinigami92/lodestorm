class_name ShipNavigation
extends Node3D
## Where the crew can walk aboard (see docs/design/crew.md): a navigation mesh over the
## ship's floors, baked from its colliders (walls, stations, furniture) once it's first asked for
## a way (`find_path`), on a worker thread; until it's done, no way is found. It lives on its own
## navigation map, so it never joins a location's (the aliens') or a station's. The ship never
## moves (the world changes around it), so it's baked once. Doors have no collision and stay open
## in it; a closed ramp or lift gate does too, it's a wall like any other. Only the decks' floors
## are kept (`FLOORS`), not the tops of tables and counters. The decks aren't joined yet (walking
## between them needs the lift, see planned/crew.md).

## The part of the ship that's baked, in ship space: the inside (both decks, without the ramp).
const BAKE_BOX := AABB(Vector3(-100.0, 1.0, -15.0), Vector3(115.0, 9.0, 30.0))
## The mesh's resolution, in m.
const CELL_SIZE: float = 0.125
const CELL_HEIGHT: float = 0.1
## How wide a walker is (it keeps this far from walls) and how tall, in m.
const AGENT_RADIUS: float = 0.375
const AGENT_HEIGHT: float = 1.8
## The decks' floors, in ship space (see game/ship/hull_layout.py: LOW, UP), and how far above or
## below one the mesh may lie, in m.
const FLOORS: Array[float] = [2.5, 7.0]
const FLOOR_TOLERANCE: float = 0.4

## The navigation map the ship's mesh is on (its own).
var map: RID

var _region: RID
var _mesh: NavigationMesh
var _baking: bool = false
var _baked: bool = false


func _ready() -> void:
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, CELL_SIZE)
	NavigationServer3D.map_set_cell_height(map, CELL_HEIGHT)
	NavigationServer3D.map_set_active(map, true)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_region, map)


func _exit_tree() -> void:
	if _region.is_valid():
		NavigationServer3D.free_rid(_region)
	if map.is_valid():
		NavigationServer3D.free_rid(map)


## Whether the mesh is baked (ways can be found).
func is_baked() -> bool:
	return _baked


## Starts baking the mesh, unless it's baked or baking already.
func bake() -> void:
	if _baking or _baked:
		return
	_baking = true
	var ship: Node3D = get_parent_node_3d()
	_mesh = NavigationMesh.new()
	_mesh.cell_size = CELL_SIZE
	_mesh.cell_height = CELL_HEIGHT
	_mesh.agent_radius = AGENT_RADIUS
	_mesh.agent_height = AGENT_HEIGHT
	_mesh.agent_max_climb = 0.3
	_mesh.agent_max_slope = 30.0
	_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	_mesh.filter_baking_aabb = BAKE_BOX
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_mesh, source, ship)
	NavigationServer3D.bake_from_source_geometry_data_async(_mesh, source, _on_baked)


## A way from `from` to `to` (global positions) over the mesh, from the closest point on it to
## each; empty until it's baked (asking starts the bake).
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not _baked:
		bake()
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map, from, to, true)


## The point of the mesh closest to `point` (global), or `point` itself until it's baked.
func closest_point(point: Vector3) -> Vector3:
	if not _baked:
		return point
	return NavigationServer3D.map_get_closest_point(map, point)


func _on_baked() -> void:
	_keep_floors()
	NavigationServer3D.region_set_transform(_region, get_parent_node_3d().global_transform)
	NavigationServer3D.region_set_navigation_mesh(_region, _mesh)
	_baking = false
	_baked = true


## Drops the mesh's polygons that aren't on a deck's floor (the tops of tables, consoles, seats).
func _keep_floors() -> void:
	var polygons: Array[PackedInt32Array] = []
	for i: int in _mesh.get_polygon_count():
		var polygon: PackedInt32Array = _mesh.get_polygon(i)
		var on_floor: bool = true
		for vertex: int in polygon:
			on_floor = on_floor and _is_floor(_mesh.vertices[vertex].y)
		if on_floor:
			polygons.append(polygon)
	_mesh.clear_polygons()
	for polygon: PackedInt32Array in polygons:
		_mesh.add_polygon(polygon)


## Whether `height` (in ship space) is on a deck's floor.
static func _is_floor(height: float) -> bool:
	for floor_y: float in FLOORS:
		if absf(height - floor_y) <= FLOOR_TOLERANCE:
			return true
	return false
