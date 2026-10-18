class_name LocationNavigation
extends NavigationRegion3D
## Bakes the walkable area of the outside world when it appears (every run gets a fresh one) from
## the static colliders under its parent: ground, bounds, rocks, nests. Aliens find their way
## around obstacles along it. Things placed later (miners) aren't part of it.

## Emitted once the walkable area is baked.
signal baked

const NO_TASK: int = -1

## Bakes on a worker thread instead of right away (a generated world takes a moment to bake, and
## the ship lands it during the flight); the region stays empty until it's done.
@export var bake_in_background: bool = false

var _baked: bool = false
## The worker thread task baking in the background, until it's done.
var _task: int = NO_TASK


func _ready() -> void:
	# Each instance bakes into its own copy; the scene's resource is shared.
	var mesh := navigation_mesh.duplicate() as NavigationMesh
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, get_parent())
	if not bake_in_background:
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
		_finish(mesh)
		return
	_task = WorkerThreadPool.add_task(
		_bake.bind(weakref(self) as WeakRef, mesh, source), false, "Bake walkable area"
	)


func _notification(what: int) -> void:
	# Quitting while a bake still runs crashes the engine on exit: a region freed mid-bake waits for
	# it (rarely: the bake is done long before the ship lands).
	if what == NOTIFICATION_PREDELETE and _task != NO_TASK:
		WorkerThreadPool.wait_for_task_completion(_task)


## Whether the walkable area is baked.
func is_baked() -> bool:
	return _baked


## Static, so the task holds no reference to a region that's gone when the bake finishes.
static func _bake(
	region: WeakRef, mesh: NavigationMesh, source: NavigationMeshSourceGeometryData3D
) -> void:
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	var alive := region.get_ref() as LocationNavigation
	if alive:
		alive._finish.call_deferred(mesh)


func _finish(mesh: NavigationMesh) -> void:
	if _task != NO_TASK:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = NO_TASK
	if not is_inside_tree():
		return
	navigation_mesh = mesh
	_baked = true
	baked.emit()
