class_name NpcTour
extends RefCounted
## A `Tour` as it runs (see `NpcRoutine`): the crew member walks ahead to the next stop and waits
## there until the player who asked for it (`leader`) is within `REACH` m, then says that stop's
## lines one after another in a bubble above their head and in their voice (each as long as a line
## moving on by itself, `Npc.say_aside`), and walks on. It's lost once the leader is gone or has
## been farther than `AWAY_RANGE` m for `AWAY_TIME` s.

## How close the leader must be for a stop's lines to start, in m. TBD (playtest).
const REACH: float = 4.0
## The leader farther than this for this long ends the tour (m, s). TBD (playtest).
const AWAY_RANGE: float = 25.0
const AWAY_TIME: float = 30.0

## Who gives it and what it is.
var npc: Npc
var tour: Tour
## The player who asked for it.
var leader: Player
## The stop they walk to or talk at (an index into `tour.stops`).
var stop: int = 0

## The line of the stop being said (-1: not yet), and the seconds it still shows.
var _line: int = -1
var _line_left: float = 0.0
## Seconds the leader has been farther than `AWAY_RANGE`.
var _away: float = 0.0


func _init(giver: Npc, listener: Player) -> void:
	npc = giver
	tour = giver.profile.tour
	leader = listener


## Where the stop they walk to or talk at is (a marker under the ship's `Tour`), or null past the
## last one.
func get_marker() -> Node3D:
	if stop >= tour.stops.size() or not npc.ship:
		return null
	return npc.ship.get_node_or_null(NodePath("Tour/" + String(tour.stops[stop].id))) as Node3D


## Whether they're saying a stop's lines right now.
func is_talking() -> bool:
	return _line >= 0


## Stops saying the stop's lines (someone talks to them); they start over once the talk is over.
func hush() -> void:
	if _line >= 0:
		npc.say_aside("")
	_line = -1


## At the stop for `delta` s: waits for the leader, then says the stop's lines and moves on to the
## next stop. Returns whether the tour is over (the last stop's lines said).
func at_stop(delta: float) -> bool:
	var lines: Array[String] = tour.stops[stop].lines
	if _line < 0:
		if leader.global_position.distance_to(npc.global_position) > REACH:
			return false
		_line = 0
		_line_left = npc.say_aside(lines[0])
		return false
	_line_left -= delta
	if _line_left > 0.0:
		return false
	_line += 1
	if _line < lines.size():
		_line_left = npc.say_aside(lines[_line])
		return false
	npc.say_aside("")
	_line = -1
	stop += 1
	return stop >= tour.stops.size()


## Whether the leader is gone (left the game, fell) or has stayed away too long (counting `delta`
## s).
func is_lost(delta: float) -> bool:
	if not is_instance_valid(leader) or leader.fallen:
		return true
	var away: bool = leader.global_position.distance_to(npc.global_position) > AWAY_RANGE
	_away = _away + delta if away else 0.0
	return _away >= AWAY_TIME
