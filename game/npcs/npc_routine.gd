class_name NpcRoutine
extends RefCounted
## Where a crew member (`npc`) is and goes aboard (see GAME_DESIGN.md, Spaceship: NPCs), each
## physics frame (`update`). They walk instead of appearing somewhere (`NpcWalker`, over the
## ship's navigation), at `WALK_SPEED`, standing while a player is within
## `NpcBody.NOTICE_RANGE` m; while someone talks to them, they stay where they are.
## With a `flight_seat` (`Npc.flight_seat`), they walk there once a destination is chosen at the
## navigator or the ship flies (faster, `HURRY_SPEED`, stopping for nobody on the way), sit down and
## wait for the course or watch the autopilot, stay seated `SEAT_LINGER` s after it has landed or
## docked (a short flight that's over before they're there: they still sit down for that long),
## get up and walk back.
## With work spots (`Npc.work_spots`), they move on now and then (every `MOVE_ON_TIME` s) from where
## they work to another of them or back to their own spot, and play there only what fits (a
## spot's `activities`, at their own spot `HOME_ACTIVITIES`); without, everything their profile
## has, at their spot.

## Walking speed, and the one on the way to the `flight_seat`, in m/s. TBD (playtest).
const WALK_SPEED: float = 1.3
const HURRY_SPEED: float = 2.0
## Seconds they stay in the `flight_seat` once the ship has landed or docked. TBD (playtest).
const SEAT_LINGER: float = 5.0
## How fast they turn to face the way their spot or seat faces (per s, smoothed).
const TURN_SPEED: float = 5.0
## What they do at their own spot when they have work spots (the crew's shared clips that need
## nothing in front of them, see tools/blender/fidgets.py).
const HOME_ACTIVITIES: Array[StringName] = [&"LookAround", &"Stretch", &"CheckWrist"]
## Seconds between moving on to another place to work (at random within this range). TBD
## (playtest).
const MOVE_ON_TIME := Vector2(20.0, 40.0)

## Whose routine it is.
var npc: Npc

## Their own spot (where the scene places them), in their parent's space.
var _home: Transform3D
## Whether they're on their way to the flight seat or sitting there (from the flight's start until
## they've sat `SEAT_LINGER` s after it), and the seconds left to sit after the flight.
var _seat_trip: bool = false
var _linger: float = 0.0
## The work spot they're at or on their way to (null: their own spot), and the seconds left until
## they move on.
var _spot: WorkSpot
var _move_on_left: float = 0.0
var _walker: NpcWalker


func _init(who: Npc) -> void:
	npc = who
	_home = who.transform
	_walker = NpcWalker.new(who, who.body)
	_move_on_left = randf_range(MOVE_ON_TIME.x, MOVE_ON_TIME.y)


## Whether they're on their way somewhere (walking, or standing for a player in the way).
func is_underway() -> bool:
	return _walker.is_underway()


## Where they want to be now (in their parent's space): the flight seat while a destination is
## chosen or the ship flies (until they've sat there `SEAT_LINGER` s after), else the work spot
## they're at (`get_work_spot`), else their own spot.
func get_post() -> Transform3D:
	var place: Node3D = npc.flight_seat if _wants_seat() else _spot
	if not place:
		return _home
	return npc.get_parent_node_3d().global_transform.affine_inverse() * place.global_transform


## The work spot they're at or on their way to, or null at their own spot.
func get_work_spot() -> WorkSpot:
	return _spot


## Moves on to another place to work: one of their work spots (not the one they're at) or their
## own spot, at random.
func move_on() -> void:
	var places: Array[WorkSpot] = [null]
	places.append_array(npc.work_spots)
	places.erase(_spot)
	var picked: WorkSpot = places.pick_random()
	_spot = picked
	_move_on_left = randf_range(MOVE_ON_TIME.x, MOVE_ON_TIME.y)


## Walks to their post (`get_post`) and takes it: facing its way, sitting down at the seat, working
## at a work spot; gets up first to leave the seat; stays put while someone talks to them.
func update(delta: float) -> void:
	var ship: Ship = npc.ship
	var body: NpcBody = npc.body
	if ship and npc.flight_seat:
		if ship.flight.is_flying() or _destination_chosen():
			_seat_trip = true
			_linger = SEAT_LINGER
		elif body.sitting and body.get_sit_amount() >= 1.0:
			_linger -= delta
			_seat_trip = _linger > 0.0
	if npc.user:
		_walker.stop()
		return
	var post: Transform3D = get_post()
	var seat: bool = _wants_seat()
	if body.sitting and not seat:
		body.sitting = false
	if body.get_sit_amount() > 0.0 and not body.sitting:
		return  # getting up
	if not seat and Player.nearest(npc.get_tree(), npc.global_position, NpcBody.NOTICE_RANGE):
		_walker.stop()
		return
	var navigation: ShipNavigation = ship.navigation if ship else null
	var speed: float = HURRY_SPEED if seat else WALK_SPEED
	if not _walker.walk_to(post.origin, speed, navigation, delta):
		return
	var yaw: float = post.basis.get_euler().y
	npc.rotation.y = lerp_angle(npc.rotation.y, yaw, 1.0 - exp(-TURN_SPEED * delta))
	if seat:
		if not body.sitting and absf(angle_difference(npc.rotation.y, yaw)) < 0.05:
			body.sitting = true
		return
	body.allow_activities(_activities_here())
	if not npc.work_spots.is_empty():
		_move_on_left -= delta
		if _move_on_left <= 0.0:
			move_on()


## What they may do where they stand (see the class description); empty: everything their
## profile has.
func _activities_here() -> Array[StringName]:
	if _spot:
		return _spot.activities
	return HOME_ACTIVITIES if not npc.work_spots.is_empty() else ([] as Array[StringName])


## Whether a destination is chosen at the navigator that the ship isn't at or flying to yet.
func _destination_chosen() -> bool:
	var voyage: Voyage = npc.ship.voyage if npc.ship else null
	return voyage != null and voyage.destination != null and voyage.destination != voyage.brief


func _wants_seat() -> bool:
	return npc.flight_seat != null and _seat_trip
