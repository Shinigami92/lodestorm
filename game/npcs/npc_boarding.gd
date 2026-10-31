class_name NpcBoarding
extends RefCounted
## A crew member walking aboard from their place before they joined (`Npc.waits_to_join`, see
## docs/design/crew.md), once their `NpcProfile.join_flag` is set: over their map's navigation
## (a station's) to the foot of the ship's ramp, waiting there while it isn't down, straight up it
## (`Ship.ramp_way`) and a step in through the door, where the ship's own crew member of their
## profile takes over (`Npc.arrive`) and walks on to their post; they're gone from their place. They
## walk at `NpcRoutine.WALK_SPEED` without stopping for players (one may follow them); out in a
## location (from their camp, over its `LocationWalkway`, their feet on its ground) at
## `OUTSIDE_SPEED`, since the run waits for them. They set off once nobody talks to them
## (`Npc.walks_aboard`).
## Without the ship standing where they are (in flight, or docked elsewhere), they're aboard at
## once, at their post (`start` returns null).
## While anyone walks aboard (`walking`), the ship doesn't leave (see `Voyage.can_confirm`) and its
## ramp can't be raised (see `Mission`); their crew member aboard isn't there yet (`is_walking`).

enum Leg { TO_RAMP, AT_RAMP, UP_RAMP, INSIDE }

## Everyone on their way aboard.
const GROUP: StringName = &"crew_boarding"
## How far past the door's sill they step in before their crew member aboard takes over, in m.
const STEP_IN: float = 0.8
## How fast they walk to the ship out in a location, in m/s. TBD (playtest).
const OUTSIDE_SPEED: float = 2.2

## Who walks aboard.
var npc: Npc
## How far they are.
var leg: Leg = Leg.TO_RAMP

var _walker: NpcWalker
var _navigation: DeckNavigation
var _ship: Ship
## Whether they've set off (see `Npc.walks_aboard`).
var _set_off: bool = false


func _init(who: Npc, walker: NpcWalker, navigation: DeckNavigation) -> void:
	npc = who
	_walker = walker
	_navigation = navigation
	_ship = who.ship


## Starts `who` walking aboard with `walker` over `navigation` (their map's), or, without the ship
## standing where they are, brings them aboard at once: null.
static func start(who: Npc, walker: NpcWalker, navigation: DeckNavigation) -> NpcBoarding:
	if not ship_here(who):
		return null
	var boarding := NpcBoarding.new(who, walker, navigation)
	who.add_to_group(GROUP)
	var aboard: Npc = crew_member(who.ship, who.profile.id)
	if aboard:
		aboard.update_presence()
	return boarding


## Whether the ship stands where `who` is: landed or docked at the location they're in.
static func ship_here(who: Npc) -> bool:
	var ship: Ship = who.ship
	var voyage: Voyage = ship.voyage if ship else null
	return (
		voyage != null
		and voyage.location != null
		and voyage.location.is_ancestor_of(who)
		and not ship.flight.is_flying()
	)


## The ship's own crew member of profile `id` (at their post once aboard), or null.
static func crew_member(ship: Ship, id: StringName) -> Npc:
	if not ship:
		return null
	for node: Node in ship.get_tree().get_nodes_in_group(Npc.CREW_GROUP):
		var found := node as Npc
		if found and not found.waits_to_join and found.profile and found.profile.id == id:
			if ship.is_ancestor_of(found):
				return found
	return null


## Everyone on their way aboard in `tree`.
static func walking(tree: SceneTree) -> Array[Npc]:
	var found: Array[Npc] = []
	for node: Node in tree.get_nodes_in_group(GROUP):
		var who := node as Npc
		if who:
			found.append(who)
	return found


## Whether the crew member of profile `id` is on their way aboard in `tree`.
static func is_walking(tree: SceneTree, id: StringName) -> bool:
	return walking(tree).any(func(who: Npc) -> bool: return who.profile.id == id)


## Stops them where they are: they aren't on their way aboard any more (their joining was taken
## back).
func cancel() -> void:
	_walker.stop()
	npc.remove_from_group(GROUP)


## Walks on for `delta` s. Returns whether they're through the door (their crew member aboard has
## taken over; they've left `GROUP`).
func update(delta: float) -> bool:
	if not is_instance_valid(_ship):
		return _hand_over()
	if not _set_off:
		_set_off = true
		npc.walks_aboard.emit()
	var way: PackedVector3Array = _ship.ramp_way()
	var foot: Vector3 = way[0]
	var sill: Vector3 = way[1]
	var outside := _navigation as LocationWalkway
	var speed: float = OUTSIDE_SPEED if outside else NpcRoutine.WALK_SPEED
	match leg:
		Leg.TO_RAMP:
			var there: bool = _walker.walk_to(foot, speed, _navigation, delta)
			if outside:
				npc.global_position.y = outside.ground_at(npc.global_position)
			if there:
				leg = Leg.AT_RAMP
		Leg.AT_RAMP:
			if _ship.is_ramp_down():
				leg = Leg.UP_RAMP
		Leg.UP_RAMP:
			var arrived: bool = _walker.walk_to(sill, speed, null, delta)
			var up: float = 1.0 if arrived else _progress(foot, sill)
			npc.global_position.y = lerpf(foot.y, sill.y, up)
			if arrived:
				leg = Leg.INSIDE
		Leg.INSIDE:
			var inside: Vector3 = sill + _ship.global_basis * Vector3.LEFT * STEP_IN
			if _walker.walk_to(inside, speed, null, delta):
				return _hand_over()
	return false


## How far along from `from` to `to` they stand (0 to 1, over the ground).
func _progress(from: Vector3, to: Vector3) -> float:
	var run := Vector2(to.x - from.x, to.z - from.z)
	var done := Vector2(npc.global_position.x - from.x, npc.global_position.z - from.z)
	return (
		clampf(done.dot(run) / run.length_squared(), 0.0, 1.0) if not run.is_zero_approx() else 1.0
	)


## Their crew member aboard takes over where they stand.
func _hand_over() -> bool:
	_walker.stop()
	npc.remove_from_group(GROUP)
	var aboard: Npc = crew_member(_ship, npc.profile.id) if is_instance_valid(_ship) else null
	if aboard:
		aboard.arrive(npc.global_transform)
	return true
