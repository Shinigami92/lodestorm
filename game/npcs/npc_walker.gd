class_name NpcWalker
extends RefCounted
## Walks an NPC (`walker`, with its `body`) to a goal (`walk_to`, global) over the navigation of
## the map they're on (`DeckNavigation`: the ship's or a station's): along the way it finds there,
## then the last step straight to the goal (a spot beside a seat or a console may lie just off the
## mesh), turning into the way it walks. While walking it opens doors (`ShipDoor.OPENERS`). The
## way is asked for again now and then until the mesh is baked, and whenever the goal changes.
## A goal on the other deck takes the lift by the lobby (`LIFT`): they walk to its gate, call the
## platform, step on once the gate is open (holding it, so it doesn't leave without them), send it
## to the other deck and ride along (their feet on the platform), step off through the gate there
## and walk on.

enum Ride { NONE, TO_GATE, WAITING, BOARDING, RIDING, LEAVING }

## How fast it turns into the way it walks (per s, smoothed).
const TURN_SPEED: float = 6.0
## How close to a point of the way counts as being there, in m.
const REACHED: float = 0.02
## Seconds between asking for a way while none is found yet (the mesh is still baking).
const RETRY_TIME: float = 0.5
## The lift they take between the decks (under the ship).
const LIFT: NodePath = ^"Lifts/NoseLift"
## How far in front of a lift's gate they wait for it, in m.
const GATE_DISTANCE: float = 1.25

## Who walks: an NPC's node and its body (its legs, the doors).
var walker: Node3D
var body: NpcBody
## Where they are with the lift (`Ride.NONE`: not taking it).
var ride: Ride = Ride.NONE

## Where it walks to (global), or INF without a goal.
var _goal: Vector3 = Vector3.INF
## The way to `_target` (global) and the point it walks to next.
var _path: PackedVector3Array = PackedVector3Array()
var _next: int = 0
var _retry_left: float = 0.0
## Where it walks to right now (the goal, or a point on the way to or from the lift).
var _target: Vector3 = Vector3.INF


func _init(who: Node3D, legs: NpcBody) -> void:
	walker = who
	body = legs


## Whether it's on its way somewhere (it has a goal it hasn't reached).
func is_underway() -> bool:
	return _goal != Vector3.INF


## Walks on towards `goal` (global; on either deck) at `speed` m/s over `navigation` for `delta`
## s. Returns whether it's there (then it stands, facing the way it came).
func walk_to(goal: Vector3, speed: float, navigation: DeckNavigation, delta: float) -> bool:
	if not goal.is_equal_approx(_goal):
		_goal = goal
		_target = Vector3.INF
		_path.clear()
		ride = Ride.NONE
	var ship: Node3D = navigation.get_parent_node_3d() if navigation else null
	var lift: Lift = ship.get_node_or_null(LIFT) as Lift if ship else null
	if ride == Ride.NONE and lift and _deck(ship, goal) != _deck(ship, walker.global_position):
		ride = Ride.TO_GATE
	if ride != Ride.NONE:
		_ride_lift(lift, ship, speed, navigation, delta)
		return false
	var flat := Vector3(goal.x, walker.global_position.y, goal.z)
	if walker.global_position.distance_to(flat) <= REACHED:
		stop()
		return true
	return _walk(goal, speed, navigation, delta, true)


## Stands where it is and forgets the way (the next `walk_to` finds a new one). Not on the lift's
## platform: they ride it to its end.
func stop() -> void:
	if ride in [Ride.BOARDING, Ride.RIDING, Ride.LEAVING]:
		_stand()
		return
	_goal = Vector3.INF
	_target = Vector3.INF
	_path.clear()
	ride = Ride.NONE
	_stand()


## One step of taking the lift to the deck of `_goal`.
func _ride_lift(
	lift: Lift, ship: Node3D, speed: float, navigation: DeckNavigation, delta: float
) -> void:
	var here: Lift.Deck = _lift_deck(ship, walker.global_position)
	var there: Lift.Deck = _lift_deck(ship, _goal)
	match ride:
		Ride.TO_GATE:
			if _walk(_gate(lift, here), speed, navigation, delta, true):
				ride = Ride.WAITING
		Ride.WAITING:
			_stand()
			if lift.is_open(here):
				ride = Ride.BOARDING
				lift.boarding = true
			else:
				lift.call_to(here)
		Ride.BOARDING:
			if not lift.is_open(here):
				_stand()
			elif _walk(lift.platform_floor(), speed, null, delta, false):
				lift.send(there)
				ride = Ride.RIDING
		Ride.RIDING:
			_stand()
			walker.global_position.y = lift.platform_floor().y
			if lift.is_open(there):
				# On the deck's floor (the platform stands a hair above it).
				var feet: Vector3 = ship.to_local(walker.global_position)
				feet.y = navigation.floors[there]
				walker.global_position = ship.to_global(feet)
				ride = Ride.LEAVING
		Ride.LEAVING:
			if _walk(_gate(lift, here), speed, null, delta, false):
				ride = Ride.NONE
				_target = Vector3.INF


## Walks towards `target` (global) for `delta` s: over the way `navigation` finds (without one:
## straight there; with `finish`, straight from the way's end to the target). Returns whether
## it's there.
func _walk(
	target: Vector3, speed: float, navigation: DeckNavigation, delta: float, finish: bool
) -> bool:
	if not target.is_equal_approx(_target):
		_target = target
		_path.clear()
		_retry_left = 0.0
	if _path.is_empty():
		if navigation:
			_retry_left -= delta
			if _retry_left > 0.0 or not _find_path(navigation, finish):
				if _retry_left <= 0.0:
					_retry_left = RETRY_TIME
				_stand()
				return false
		else:
			_path = PackedVector3Array([target])
			_next = 0
	var left: float = speed * delta
	while left > 0.0 and _next < _path.size():
		var point: Vector3 = _path[_next]
		var at: Vector3 = walker.global_position
		var offset := Vector3(point.x - at.x, 0.0, point.z - at.z)
		if offset.length() <= maxf(left, REACHED):
			walker.global_position = Vector3(point.x, at.y, point.z)
			left -= offset.length()
			_next += 1
			continue
		var way: Vector3 = offset.normalized()
		walker.global_position = at + way * left
		left = 0.0
		_face(way, delta)
	if _next >= _path.size():
		_target = Vector3.INF
		_path.clear()
		_stand()
		return true
	body.walk(speed)
	body.add_to_group(ShipDoor.OPENERS)
	return false


## Turns towards `way` (global), smoothed.
func _face(way: Vector3, delta: float) -> void:
	var parent: Node3D = walker.get_parent_node_3d()
	var local: Vector3 = parent.global_basis.inverse() * way if parent else way
	walker.rotation.y = lerp_angle(
		walker.rotation.y, atan2(local.x, local.z), 1.0 - exp(-TURN_SPEED * delta)
	)


func _stand() -> void:
	body.walk(0.0)
	body.remove_from_group(ShipDoor.OPENERS)


## Finds the way to `_target` over `navigation` (and, with `finish`, the target itself after it).
## Returns whether it found one.
func _find_path(navigation: DeckNavigation, finish: bool) -> bool:
	var points: PackedVector3Array = navigation.find_path(walker.global_position, _target)
	if points.is_empty():
		return false
	_path = points
	if finish:
		_path.append(_target)
	_next = 0
	return true


## Where they wait in front of the lift's gate on `deck` (global, on its floor).
static func _gate(lift: Lift, deck: Lift.Deck) -> Vector3:
	return lift.gate_floor(deck) + lift.global_basis.z * GATE_DISTANCE


## Which of the ship's decks `point` (global) is on: 0 lower, 1 upper.
static func _deck(ship: Node3D, point: Vector3) -> int:
	return 1 if ship.to_local(point).y >= Ship.UPPER_DECK_HEIGHT else 0


static func _lift_deck(ship: Node3D, point: Vector3) -> Lift.Deck:
	return Lift.Deck.UPPER if _deck(ship, point) == 1 else Lift.Deck.LOWER
