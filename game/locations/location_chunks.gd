class_name LocationChunks
extends RefCounted
## The chunks a generated location's many small things (plants, rocks, cliffs, the fence) are cut
## into, `GeneratedLocation.CHUNK_CELLS` grid cells a side, so the ones out of view are culled: one
## `MultiMeshInstance3D` per mesh and chunk (`instance`), named after the mesh and the chunk.


## The chunk of `terrain` that `at` (x, z) lies in.
static func of(terrain: LocationTerrain, at: Vector2) -> Vector2i:
	var size: float = GeneratedLocation.CHUNK_CELLS * terrain.cell
	return Vector2i(((at - terrain.origin) / size).floor())


## Adds `placed` to the transforms of chunk `key` in `by_chunk` (keys of any type, values Arrays).
static func add(by_chunk: Dictionary, key: Variant, placed: Transform3D) -> void:
	if not by_chunk.has(key):
		by_chunk[key] = []
	var in_chunk: Array = by_chunk[key]
	in_chunk.append(placed)


## The node name of `prefix`'s instance in chunk `chunk` ("Fence3_-2").
static func node_name(prefix: String, chunk: Vector2i) -> String:
	return "%s%d_%d" % [prefix, chunk.x, chunk.y]


## A `MultiMeshInstance3D` named `name_of_node` with `mesh` at each of `transforms`
## (`Transform3D`s).
static func instance(mesh: Mesh, transforms: Array, name_of_node: String) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i: int in transforms.size():
		var placed: Transform3D = transforms[i]
		multimesh.set_instance_transform(i, placed)
	var made := MultiMeshInstance3D.new()
	made.name = name_of_node
	made.multimesh = multimesh
	return made
