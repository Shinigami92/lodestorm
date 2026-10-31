class_name LocationWalkway
extends DeckNavigation
## Where people walk out in a generated location (someone walking from their camp to the ship, see
## `NpcBoarding`): the location's own walkable area, the one the aliens find their way on
## (`LocationNavigation`), so the way follows the passes; nothing of its own is baked. The ground
## is uneven, so a walker's feet follow it (`ground_at`).

## The location's walkable area (the aliens').
var region: LocationNavigation
## The location it's in (its ground).
var location: GeneratedLocation


func _ready() -> void:
	# No navigation map of its own: the location's is used.
	set_physics_process(false)


func is_baked() -> bool:
	return region != null and region.is_baked()


func bake() -> void:
	pass


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not is_baked():
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(region.get_navigation_map(), from, to, true)


func closest_point(point: Vector3) -> Vector3:
	if not is_baked():
		return point
	return NavigationServer3D.map_get_closest_point(region.get_navigation_map(), point)


## The ground's height under `point` (global), in m (global).
func ground_at(point: Vector3) -> float:
	if not location or not location.terrain:
		return point.y
	var local: Vector3 = location.to_local(point)
	local.y = location.terrain.height_at(local.x, local.z)
	return location.to_global(local).y
