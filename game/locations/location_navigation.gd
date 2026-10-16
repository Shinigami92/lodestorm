class_name LocationNavigation
extends NavigationRegion3D
## Bakes the walkable area of the outside world when it appears (every run gets a fresh one) from
## the static colliders under its parent: ground, bounds, rocks, nests. Aliens find their way
## around obstacles along it. Things placed later (miners) aren't part of it.

## Emitted once the walkable area is baked.
signal baked

## Bakes on a worker thread instead of right away (a generated world takes a moment to bake, and
## the ship lands it during the flight); the region stays empty until it's done.
@export var bake_in_background: bool = false

var _baked: bool = false


func _ready() -> void:
	# Each instance bakes into its own copy; the scene's resource is shared.
	var mesh := navigation_mesh.duplicate() as NavigationMesh
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, get_parent())
	if not bake_in_background:
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
		_finish(mesh)
		return
	_bake_in_background(weakref(self) as WeakRef, mesh, source)


## Whether the walkable area is baked.
func is_baked() -> bool:
	return _baked


## Static, so the callback holds no reference to a region that's gone when the bake finishes.
static func _bake_in_background(
	region: WeakRef, mesh: NavigationMesh, source: NavigationMeshSourceGeometryData3D
) -> void:
	NavigationServer3D.bake_from_source_geometry_data_async(
		mesh,
		source,
		func() -> void:
			var alive := region.get_ref() as LocationNavigation
			if alive:
				alive._finish.call_deferred(mesh)
	)


func _finish(mesh: NavigationMesh) -> void:
	if not is_inside_tree():
		return
	navigation_mesh = mesh
	_baked = true
	baked.emit()
