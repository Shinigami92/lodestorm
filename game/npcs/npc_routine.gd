class_name NpcRoutine
extends RefCounted
## Where a crew member (`npc`) is and goes aboard (see GAME_DESIGN.md, Spaceship: NPCs), each
## physics frame (`update`). They walk instead of appearing somewhere (`NpcWalker`, over the
## ship's navigation, taking the lift between the decks), at `WALK_SPEED`, standing while a player
## is within `NpcBody.NOTICE_RANGE` m; while someone talks to them, they stay where they are.
## With a `flight_seat` (`Npc.flight_seat`), they walk there once a destination is chosen at the
## navigator or the ship flies (faster, `HURRY_SPEED`, stopping for nobody on the way), sit down and
## wait for the course or watch the autopilot, stay seated `SEAT_LINGER` s after it has landed or
## docked (a short flight that's over before they're there: they still sit down for that long),
## get up and walk back.
## With a `Tour` (their profile's), they wait at its start until its offer is heard (a new game
## starts them there), and while it runs (`start_tour`, an `NpcTour`) they walk ahead from stop to
## stop (faster, stopping for nobody: they lead) and say each stop's lines, then go back to their
## spot.
## With work spots (`Npc.work_spots`), they move on now and then (every `MOVE_ON_TIME` s) from where
## they work to another of them or back to their own spot, and play there only what fits (a
## spot's `activities`, at their own spot `HOME_ACTIVITIES`); without, everything their profile
## has, at their spot.

## Walking speed, and the one on the way to the `flight_seat` and leading a tour, in m/s. TBD
## (playtest).
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
## The tour they give right now, or null.
var tour: NpcTour

## Their own spot (where the scene places them), global (the ship never moves).
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
## Whether the first update placed them (at the tour's start on a new game: the save is read by
## then).
var _settled: bool = false


func _init(who: Npc) -> void:
	npc = who
	_home = who.global_transform
	_walker = NpcWalker.new(who, who.body)
	_move_on_left = randf_range(MOVE_ON_TIME.x, MOVE_ON_TIME.y)


## Whether they're on their way somewhere (walking, or standing for a player in the way).
func is_underway() -> bool:
	return _walker.is_underway()


## Whether they wait at their tour's start for its offer to be heard (a new game).
func is_waiting() -> bool:
	var given: Tour = npc.profile.tour if npc.profile else null
	return given != null and tour == null and not npc.get_story().is_set(given.offer.id)


## Where they want to be now (global): the flight seat while a destination is chosen or the ship
## flies (until they've sat there `SEAT_LINGER` s after), else the tour's stop or start, else the
## work spot they're at (`get_work_spot`), else their own spot.
func get_post() -> Transform3D:
	var place: Node3D = _spot
	if _wants_seat():
		place = npc.flight_seat
	elif tour:
		place = tour.get_marker()
	elif is_waiting() and npc.ship:
		place = npc.ship.get_node_or_null(NodePath("Tour/" + String(npc.profile.tour.start)))
	return place.global_transform if place else _home


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


## Starts their profile's tour for `leader`, from its first stop.
func start_tour(leader: Player) -> void:
	if npc.profile and npc.profile.tour and leader:
		tour = NpcTour.new(npc, leader)
		_spot = null


## Ends the tour (done, lost or asked for); they go back to their spot.
func end_tour() -> void:
	if tour:
		tour.hush()
	tour = null


## Walks to their post (`get_post`) and takes it: facing its way, sitting down at the seat, talking
## at a tour's stop, working at a work spot; gets up first to leave the seat; stays put while
## someone talks to them.
func update(delta: float) -> void:
	var ship: Ship = npc.ship
	var body: NpcBody = npc.body
	if not _settled:
		_settled = true
		if is_waiting():
			npc.global_transform = get_post()
			npc.reset_physics_interpolation()
	_count_seat_trip(delta)
	if tour and tour.is_lost(delta):
		end_tour()
	if npc.user:
		_walker.stop()
		if tour:
			tour.hush()
		return
	var post: Transform3D = get_post()
	var seat: bool = _wants_seat()
	if body.sitting and not seat:
		body.sitting = false
	if body.get_sit_amount() > 0.0 and not body.sitting:
		return  # getting up
	var leads: bool = seat or tour != null
	if not leads and Player.nearest(npc.get_tree(), npc.global_position, NpcBody.NOTICE_RANGE):
		_walker.stop()
		return
	var navigation: ShipNavigation = ship.navigation if ship else null
	var speed: float = HURRY_SPEED if leads else WALK_SPEED
	if not _walker.walk_to(post.origin, speed, navigation, delta):
		return
	var parent: Node3D = npc.get_parent_node_3d()
	var yaw: float = (parent.global_basis.inverse() * post.basis).get_euler().y
	npc.rotation.y = lerp_angle(npc.rotation.y, yaw, 1.0 - exp(-TURN_SPEED * delta))
	if seat:
		if not body.sitting and absf(angle_difference(npc.rotation.y, yaw)) < 0.05:
			body.sitting = true
		return
	if tour:
		body.allow_activities([&"Nothing"] as Array[StringName])
		if tour.at_stop(delta):
			end_tour()
		return
	body.allow_activities(_activities_here())
	if not npc.work_spots.is_empty() and not is_waiting():
		_move_on_left -= delta
		if _move_on_left <= 0.0:
			move_on()


## Keeps track of the trip to the flight seat (see `_seat_trip`).
func _count_seat_trip(delta: float) -> void:
	if not npc.ship or not npc.flight_seat:
		return
	if npc.ship.flight.is_flying() or _destination_chosen():
		_seat_trip = true
		_linger = SEAT_LINGER
	elif npc.body.sitting and npc.body.get_sit_amount() >= 1.0:
		_linger -= delta
		_seat_trip = _linger > 0.0


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
