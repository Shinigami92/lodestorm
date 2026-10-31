class_name NpcRoutine
extends RefCounted
## Where a crew member (`npc`) is and goes aboard (see docs/design/crew.md), each
## physics frame (`update`). They walk instead of appearing somewhere (`NpcWalker`, over the
## ship's navigation, taking the lift between the decks), at `WALK_SPEED`, standing while a player
## is within `NpcBody.NOTICE_RANGE` m (not on the way to a talk's spot); while someone talks to
## them, they stay where they are.
## With a `flight_seat` (`Npc.flight_seat`), they walk there once a destination is chosen at the
## navigator or the ship flies (faster, `HURRY_SPEED`, stopping for nobody on the way), sit down and
## wait for the course or watch the autopilot, stay seated `SEAT_LINGER` s after it has landed or
## docked (a short flight that's over before they're there: they still sit down for that long),
## get up and walk back.
## With a `Tour` (their profile's), they wait at its start until its offer is heard (a new game
## starts them there), and while it runs (`start_tour`, an `NpcTour`) they walk ahead from stop to
## stop (faster, stopping for nobody: they lead) and say each stop's lines, then go back to their
## spot.
## With an overheard talk waiting for them (`talk_place`, see `OverheardTalks`), they walk to their
## place at its spot and wait there, doing nothing else; while it plays (`Npc.overheard`) they stay
## put, even for the flight seat.
## With work spots (`Npc.work_spots`), they move on now and then (every `MOVE_ON_TIME` s) from where
## they work to another of them or back to their own spot (each as likely as its `weight`; one
## outside their own room only once their greeting is heard), and play there only what fits (a
## spot's `activities`, at their own spot `Npc.home_activities` or `HOME_ACTIVITIES`); without,
## everything their profile has, at their spot. Away from their own spot (and on the way), they're
## used at their feet (`Npc.use_point` within `USE_RANGE` m), unless the spot is `use_like_home`.
## They walk over the navigation of the map they're on (the ship's, a station's: `DeckNavigation`);
## a station's people's spots move with it (it glides in while the ship docks).
## Seated (`Npc.seated`), they sit at their own spot (on the seat behind it) and get up to go.
## At their place before joining (`Npc.waits_to_join`), once they join they get up and walk aboard
## (`start_boarding`, an `NpcBoarding`); aboard, their crew member taking over at the door
## (`arrive`) walks on to their post without stopping for players.
## They know which room they stand in (`get_room`, from their map's `RoomPlan`) and whether it's
## their own (`is_away`: the room of their own spot), so what they say fits where they are (see
## `Topic.away_lines`).

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
## How far from their feet they're used away from their own spot (npc.tscn's "Use"), in m.
const USE_RANGE: float = 1.8
## How close to their place for an overheard talk they count as there, in m.
const TALK_PLACE_REACH: float = 0.3

## Whose routine it is.
var npc: Npc
## The tour they give right now, or null.
var tour: NpcTour
## Their place at the spot of an overheard talk waiting for them, or null.
var talk_place: Node3D
## Their walk aboard from their place before joining, or null.
var boarding: NpcBoarding

## Their own spot (where the scene places them), in their parent's space.
var _home: Transform3D
## Whether they're on their way to the flight seat or sitting there (from the flight's start until
## they've sat `SEAT_LINGER` s after it), and the seconds left to sit after the flight.
var _seat_trip: bool = false
## Whether they came aboard at the door and walk on to their post (stopping for nobody).
var _arriving: bool = false
var _linger: float = 0.0
## The work spot they're at or on their way to (null: their own spot), and the seconds left until
## they move on.
var _spot: WorkSpot
var _move_on_left: float = 0.0
var _walker: NpcWalker
## Whether the first update placed them (at the tour's start on a new game: the save is read by
## then).
var _settled: bool = false
## The map they're on (the ship or a station, found when first needed), its rooms, the room they
## stand in (kept through doorways) and the one of their own spot.
var _map: Node3D
var _plan: RoomPlan
var _room: StringName = &""
var _own_room: StringName = &""
## How they're used at their own spot (the scene's "Use": where, how far, its footprint, and its
## highlight), and whether it's placed that way now.
var _use_home: Transform3D
var _use_range: float = USE_RANGE
var _use_footprint: Vector2 = Vector2.ZERO
var _highlight_home: Vector3 = Vector3.ZERO
var _used_home: bool = true


func _init(who: Npc) -> void:
	npc = who
	_home = who.transform
	_walker = NpcWalker.new(who, who.body)
	_move_on_left = randf_range(MOVE_ON_TIME.x, MOVE_ON_TIME.y)
	var use: Interactable = who.use_point
	if use:
		_use_home = use.transform
		_use_range = use.interact_range
		_use_footprint = use.footprint
		var highlight := use.get_node_or_null(^"Highlight") as Node3D
		_highlight_home = highlight.position if highlight else Vector3.ZERO


## Whether they're on their way somewhere (walking, or standing for a player in the way).
func is_underway() -> bool:
	return _walker.is_underway()


## Whether they wait at their tour's start for its offer to be heard (a new game).
func is_waiting() -> bool:
	var given: Tour = npc.profile.tour if npc.profile else null
	return given != null and tour == null and not npc.get_story().is_set(given.offer.id)


## The room they stand in (its node name in the map, e.g. "Armory"; in a doorway still the one
## they come from), or "" on a map without rooms.
func get_room() -> StringName:
	var plan: RoomPlan = _get_plan()
	if plan:
		_room = plan.room_at(npc.global_position, _room)
	return _room


## The room their own spot is in, or "" on a map without rooms.
func get_own_room() -> StringName:
	var plan: RoomPlan = _get_plan()
	if plan and _own_room.is_empty():
		_own_room = plan.room_at(_get_home().origin)
	return _own_room


## Whether they stand outside their own room (what they say there must fit without it).
func is_away() -> bool:
	var own: StringName = get_own_room()
	return not own.is_empty() and get_room() != own


## Where they want to be now (global): the flight seat while a destination is chosen or the ship
## flies (until they've sat there `SEAT_LINGER` s after), else the tour's stop or start, else their
## place at an overheard talk's spot (`talk_place`), else the work spot they're at
## (`get_work_spot`), else their own spot.
func get_post() -> Transform3D:
	var place: Node3D = talk_place if talk_place else _spot
	if _wants_flight_seat():
		place = npc.flight_seat
	elif tour:
		place = tour.get_marker()
	elif is_waiting() and npc.ship:
		place = npc.ship.get_node_or_null(NodePath("Tour/" + String(npc.profile.tour.start)))
	return place.global_transform if place else _get_home()


## Whether they stand at their place for an overheard talk (`talk_place`), facing its way.
func is_at_talk_place() -> bool:
	if not talk_place or is_underway() or npc.body.sitting:
		return false
	var place: Transform3D = talk_place.global_transform
	if place.origin.distance_to(npc.global_position) > TALK_PLACE_REACH:
		return false
	var parent: Node3D = npc.get_parent_node_3d()
	var yaw: float = (parent.global_basis.inverse() * place.basis).get_euler().y
	return absf(angle_difference(npc.rotation.y, yaw)) < 0.1


## The work spot they're at or on their way to, or null at their own spot.
func get_work_spot() -> WorkSpot:
	return _spot


## Moves on to another place to work: one of their work spots (not the one they're at; one outside
## their own room only once their greeting is heard) or their own spot, at random by the spots'
## `weight` (their own spot's is 1).
func move_on() -> void:
	var places: Array[WorkSpot] = [null]
	var greeted: bool = _greeted()
	for spot: WorkSpot in npc.work_spots:
		if greeted or _room_of(spot) == get_own_room():
			places.append(spot)
	places.erase(_spot)
	var total: float = 0.0
	for place: WorkSpot in places:
		total += place.weight if place else 1.0
	var roll: float = randf() * total
	_spot = places.back() if not places.is_empty() else null
	for place: WorkSpot in places:
		roll -= place.weight if place else 1.0
		if roll < 0.0:
			_spot = place
			break
	_move_on_left = randf_range(MOVE_ON_TIME.x, MOVE_ON_TIME.y)


## Starts their profile's tour for `leader`, from its first stop.
func start_tour(leader: Player) -> void:
	if npc.profile and npc.profile.tour and leader:
		tour = NpcTour.new(npc, leader)
		_spot = null


## Starts their walk aboard (they've joined; see `NpcBoarding.start`: none without the ship where
## they are).
func start_boarding() -> void:
	end_tour()
	_spot = null
	talk_place = null
	boarding = NpcBoarding.start(npc, _walker, _get_navigation())


## They've come aboard at the door (see `Npc.arrive`): on to their post, stopping for nobody.
func arrive() -> void:
	_walker.stop()
	_spot = null
	_arriving = true


## Ends the tour (done, lost or asked for); they go back to their spot.
func end_tour() -> void:
	if tour:
		tour.hush()
	tour = null


## Walks to their post (`get_post`) and takes it: facing its way, sitting down at the seat, talking
## at a tour's stop, working at a work spot; gets up first to leave the seat; stays put while
## someone talks to them.
func update(delta: float) -> void:
	var body: NpcBody = npc.body
	if not _settled:
		_settled = true
		if is_waiting():
			npc.global_transform = get_post()
			npc.reset_physics_interpolation()
		elif _sits_at_home():
			body.sitting = true
			body.settle()
	_count_seat_trip(delta)
	if tour and tour.is_lost(delta):
		end_tour()
	_place_use()
	if npc.user or npc.overheard:
		_walker.stop()
		if tour:
			tour.hush()
		return
	var post: Transform3D = get_post()
	var flight_seat: bool = _wants_flight_seat()
	var seat: bool = flight_seat or _sits_at_home()
	if body.sitting and not seat:
		body.sitting = false
	# Getting up first; walking aboard goes its own way.
	if (body.get_sit_amount() > 0.0 and not body.sitting) or _walk_aboard(delta):
		return
	var leads: bool = flight_seat or tour != null
	# On the way to a talk they don't stand for players either: one may wait at its spot.
	var keeps_on: bool = leads or talk_place != null or _arriving
	if not keeps_on and Player.nearest(npc.get_tree(), npc.global_position, NpcBody.NOTICE_RANGE):
		_walker.stop()
		return
	var navigation: DeckNavigation = _get_navigation()
	var speed: float = HURRY_SPEED if leads else WALK_SPEED
	if not _walker.walk_to(post.origin, speed, navigation, delta):
		return
	_arriving = false
	_place_use()
	var parent: Node3D = npc.get_parent_node_3d()
	var yaw: float = (parent.global_basis.inverse() * post.basis).get_euler().y
	npc.rotation.y = lerp_angle(npc.rotation.y, yaw, 1.0 - exp(-TURN_SPEED * delta))
	if seat:
		if not body.sitting and absf(angle_difference(npc.rotation.y, yaw)) < 0.05:
			body.sitting = true
		return
	if tour or talk_place:
		body.allow_activities([&"Nothing"] as Array[StringName])
		if tour and tour.at_stop(delta):
			end_tour()
		return
	body.allow_activities(_activities_here())
	if not npc.work_spots.is_empty() and not is_waiting():
		_move_on_left -= delta
		if _move_on_left <= 0.0:
			move_on()


## Walks on aboard for `delta` s while they do (`boarding`), gone once through the door. Returns
## whether they did.
func _walk_aboard(delta: float) -> bool:
	if not boarding:
		return false
	if boarding.update(delta):
		boarding = null
		npc.update_presence()
	return true


## Their own spot, global.
func _get_home() -> Transform3D:
	var parent: Node3D = npc.get_parent_node_3d()
	return parent.global_transform * _home if parent else _home


## The rooms of the ship or station they're on, or null.
func _get_plan() -> RoomPlan:
	if not _plan:
		var map: Node3D = _get_map()
		if map is Ship:
			_plan = (map as Ship).room_plan
		elif map is SpaceStation:
			_plan = (map as SpaceStation).room_plan
	return _plan


## Where they walk on the ship or station they're on, or null (straight to where they go).
func _get_navigation() -> DeckNavigation:
	var map: Node3D = _get_map()
	if map is Ship:
		return (map as Ship).navigation
	if map is SpaceStation:
		return (map as SpaceStation).navigation
	return null


## The ship or station they're on (the nearest one above them), or null.
func _get_map() -> Node3D:
	var at: Node = npc.get_parent() if not _map else null
	while at and not _map:
		if at is Ship or at is SpaceStation:
			_map = at as Node3D
		at = at.get_parent()
	return _map


## The room `spot` is in.
func _room_of(spot: WorkSpot) -> StringName:
	var plan: RoomPlan = _get_plan()
	return plan.room_at(spot.global_position) if plan else &""


## Whether their greeting is heard (or they have none).
func _greeted() -> bool:
	var dialogue: Dialogue = npc.profile.dialogue if npc.profile else null
	return not dialogue or not dialogue.greeting or npc.get_story().is_set(dialogue.greeting.id)


## Places where they're used: as at their own spot while they're there (or at a `use_like_home`
## spot), else at their feet.
func _place_use() -> void:
	var use: Interactable = npc.use_point
	var home: bool = not is_underway() and (not _spot or _spot.use_like_home)
	if not use or home == _used_home:
		return
	_used_home = home
	use.transform = _use_home if home else Transform3D.IDENTITY
	use.interact_range = _use_range if home else USE_RANGE
	use.footprint = _use_footprint if home else Vector2.ZERO
	var highlight := use.get_node_or_null(^"Highlight") as Node3D
	if highlight:
		highlight.position = _highlight_home if home else Vector3(0.0, 0.02, 0.0)


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
	if npc.work_spots.is_empty():
		return [] as Array[StringName]
	return npc.home_activities if not npc.home_activities.is_empty() else HOME_ACTIVITIES


## Whether a destination is chosen at the navigator that the ship isn't at or flying to yet.
func _destination_chosen() -> bool:
	var voyage: Voyage = npc.ship.voyage if npc.ship else null
	return voyage != null and voyage.destination != null and voyage.destination != voyage.brief


func _wants_flight_seat() -> bool:
	return npc.flight_seat != null and _seat_trip


## Whether they sit at their own spot now: seated (`Npc.seated`) and nowhere else to be.
func _sits_at_home() -> bool:
	return (
		npc.seated
		and not boarding
		and not tour
		and not _spot
		and not talk_place
		and not _arriving
		and not _wants_flight_seat()
	)
