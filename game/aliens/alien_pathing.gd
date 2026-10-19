class_name AlienPathing
extends RefCounted
## How an alien finds its way (`Alien`'s helper): along the navigation mesh where there is one (its
## `NavigationAgent3D`), straight otherwise, and fliers always straight. Looking up a path is
## expensive: both ends are searched among all of the walkable area's polygons (about 0.5 ms on a
## generated world), so a path is only looked up again once the point moved far enough, and only a
## few aliens may look one up per physics frame. Values TBD (playtest).

## The path is only looked up again once the point moved this far (m), or this share of the way
## to it if that's more: far away, a little off doesn't matter.
const REPATH_DISTANCE: float = 1.0
const REPATH_SHARE: float = 0.2
## At most this many aliens look up a path per physics frame; the others follow their old one a
## frame longer.
const PATHS_PER_FRAME: int = 2
## How far ahead it looks for a spot to back off to (m), and how long that spot holds (s).
const BACK_OFF_STEP: float = 5.0
const BACK_OFF_HOLD: float = 0.5

## The physics frame the path budget is for, and the look-ups left in it.
static var _path_frame: int = -1
static var _paths_left: int = 0
## Whether the navigation map had a walkable area in the physics frame it was last asked for.
static var _navigation_frame: int = -1
static var _navigation_map := RID()
static var _navigation_found: bool = false

var _alien: Alien
var _agent: NavigationAgent3D
## Whether the agent has a target: until then it goes straight.
var _pathing: bool = false
## The spot it backs off to, and the seconds it still holds.
var _away_spot := Vector3.ZERO
var _away_left: float = 0.0


func _init(alien: Alien, agent: NavigationAgent3D) -> void:
	_alien = alien
	_agent = agent


## Whether `alien` walks along a navigation mesh: there is one, and it doesn't fly.
static func has_navigation(alien: Alien) -> bool:
	if alien.strain.flies():
		return false
	var map: RID = alien.get_world_3d().navigation_map
	var frame: int = Engine.get_physics_frames()
	if frame != _navigation_frame or map != _navigation_map:
		_navigation_frame = frame
		_navigation_map = map
		_navigation_found = not NavigationServer3D.map_get_regions(map).is_empty()
	return _navigation_found


## Counts the spot to back off to down.
func tick(delta: float) -> void:
	_away_left = maxf(_away_left - delta, 0.0)


## Horizontal direction towards `point`: along the navigation mesh if there is one and it has a
## path, straight otherwise.
func direction_to(point: Vector3) -> Vector3:
	var from: Vector3 = _alien.global_position
	var next: Vector3 = point
	if has_navigation(_alien):
		var moved: float = _agent.target_position.distance_to(point) if _pathing else INF
		var enough: float = maxf(REPATH_DISTANCE, from.distance_to(point) * REPATH_SHARE)
		if moved > enough and _may_look_up_path():
			_agent.target_position = point
			_pathing = true
		if _pathing:
			next = _agent.get_next_path_position()
	var offset: Vector3 = next - from
	offset.y = 0.0
	if offset.length() < 0.01:
		offset = point - from
		offset.y = 0.0
	return offset.normalized()


## Horizontal direction to back off from `node`: towards a spot farther away (along the navigation
## mesh if there is one), picked anew every `BACK_OFF_HOLD`.
func direction_away_from(node: Node3D) -> Vector3:
	if _away_left == 0.0:
		var away := Vector3.ZERO
		if is_instance_valid(node):
			away = _alien.global_position - node.global_position
		away.y = 0.0
		if away.length() < 0.01:
			away = _alien.global_basis.z
		_away_spot = _alien.global_position + away.normalized() * BACK_OFF_STEP
		_away_left = BACK_OFF_HOLD
	return direction_to(_away_spot)


## Whether the frame's budget allows another path look-up; takes it.
static func _may_look_up_path() -> bool:
	var frame: int = Engine.get_physics_frames()
	if frame != _path_frame:
		_path_frame = frame
		_paths_left = PATHS_PER_FRAME
	if _paths_left == 0:
		return false
	_paths_left -= 1
	return true
