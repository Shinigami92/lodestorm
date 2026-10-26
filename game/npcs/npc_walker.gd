class_name NpcWalker
extends RefCounted
## Walks a crew member (`walker`, with its `body`) aboard to a goal (`go`) over the ship's
## navigation (`ShipNavigation`): along the way it finds there, then the last step straight to the
## goal (a spot beside a seat or a console may lie just off the mesh), turning into the way it
## walks. While walking it opens doors (`ShipDoor.OPENERS`). The way is asked for again now and then
## until the mesh is baked, and whenever the goal changes.

## How fast it turns into the way it walks (per s, smoothed).
const TURN_SPEED: float = 6.0
## How close to a point of the way counts as being there, in m.
const REACHED: float = 0.02
## Seconds between asking for a way while none is found yet (the mesh is still baking).
const RETRY_TIME: float = 0.5

## Who walks: an NPC's node (moved in its parent's space) and its body (its legs, the doors).
var walker: Node3D
var body: NpcBody

## Where it walks to, in its parent's space.
var _goal: Vector3 = Vector3.INF
## The way there, in its parent's space, and the point it walks to next.
var _path: PackedVector3Array = PackedVector3Array()
var _next: int = 0
var _retry_left: float = 0.0


func _init(who: Node3D, legs: NpcBody) -> void:
	walker = who
	body = legs


## Whether it's on its way somewhere (it has a goal it hasn't reached).
func is_underway() -> bool:
	return _goal != Vector3.INF


## Walks on towards `goal` (in its parent's space) at `speed` m/s over `navigation` for `delta` s.
## Returns whether it's there (then it stands, facing the way it came).
func walk_to(goal: Vector3, speed: float, navigation: ShipNavigation, delta: float) -> bool:
	var flat := Vector3(goal.x, walker.position.y, goal.z)
	if walker.position.distance_to(flat) <= REACHED:
		stop()
		return true
	if not goal.is_equal_approx(_goal):
		_goal = goal
		_path.clear()
		_retry_left = 0.0
	if _path.is_empty():
		_retry_left -= delta
		if _retry_left > 0.0:
			_stand()
			return false
		if not _find_path(navigation):
			_retry_left = RETRY_TIME
			_stand()
			return false
	var left: float = speed * delta
	while left > 0.0 and _next < _path.size():
		var target: Vector3 = _path[_next]
		var offset := Vector3(target.x - walker.position.x, 0.0, target.z - walker.position.z)
		if offset.length() <= maxf(left, REACHED):
			walker.position = Vector3(target.x, walker.position.y, target.z)
			left -= offset.length()
			_next += 1
			continue
		var way: Vector3 = offset.normalized()
		walker.position += way * left
		left = 0.0
		walker.rotation.y = lerp_angle(
			walker.rotation.y, atan2(way.x, way.z), 1.0 - exp(-TURN_SPEED * delta)
		)
	if _next >= _path.size():
		stop()
		return true
	body.walk(speed)
	body.add_to_group(ShipDoor.OPENERS)
	return false


## Stands where it is and forgets the way (the next `walk_to` finds a new one).
func stop() -> void:
	_goal = Vector3.INF
	_path.clear()
	_stand()


func _stand() -> void:
	body.walk(0.0)
	body.remove_from_group(ShipDoor.OPENERS)


## Finds the way to `_goal` over `navigation`: its points in the parent's space, then the goal
## itself. Returns whether it found one.
func _find_path(navigation: ShipNavigation) -> bool:
	if not navigation:
		return false
	var parent: Node3D = walker.get_parent_node_3d()
	var to_global: Transform3D = parent.global_transform if parent else Transform3D.IDENTITY
	var points: PackedVector3Array = navigation.find_path(walker.global_position, to_global * _goal)
	if points.is_empty():
		return false
	_path.clear()
	for point: Vector3 in points:
		_path.append(to_global.affine_inverse() * point)
	_path.append(_goal)
	_next = 0
	return true
