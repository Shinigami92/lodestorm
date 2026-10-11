class_name LocationNavigation
extends NavigationRegion3D
## Bakes the walkable area of the outside world when it appears (every run gets a fresh one) from
## the static colliders under its parent: ground, bounds, rocks, nests. Aliens find their way
## around obstacles along it. Things placed later (miners) aren't part of it.


func _ready() -> void:
	# Each instance bakes into its own copy; the scene's resource is shared.
	var mesh := navigation_mesh.duplicate() as NavigationMesh
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, get_parent())
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	navigation_mesh = mesh
