class_name Colonist
extends Node3D
## One of a station's ambient colonists (see docs/design/station.md): the
## `NpcBody` that `profile` says (a role on the plate, no name), standing at its spot, sitting there
## (`seated`: on the seat behind it, e.g. a bench or a booth) or walking its `route` round and
## round, with a short stop at every waypoint (sitting down for a while at its `seat_stop`). It
## stops while a player is close (turning towards them, like the crew, unless it sits) instead of
## walking into them. When a player stops next to it, it says one of its profile's `remarks` in a
## speech bubble (above its head, lower while it sits), which stays until they walk off; the next
## one comes when a player comes back. The bubble grows with the camera's view,
## so it reads like a crew member's while talking to them. No talking (it's no station).

## Walking speed, in m/s.
const WALK_SPEED: float = 1.3
## How long it stops at each waypoint, in s.
const STOP_TIME: float = 3.0
## How fast it turns into the way it walks (per s, smoothed).
const TURN_SPEED: float = 4.0
## How close (in m) a player must be for a remark.
const REMARK_RANGE: float = 2.0
## How slow (in m/s) a player close by must be to count as stopping there.
const STILL_SPEED: float = 0.5
## How far (in m) the player has to walk off for the remark to end (a little farther than
## `REMARK_RANGE`, so it doesn't flicker at the edge).
const LEAVE_RANGE: float = 2.6

## Who it is: its role, suit and remarks.
@export var profile: NpcProfile
## Multiplies its profile's suit tint (colonists of one role in different suits).
@export var tint: Color = Color.WHITE
## The waypoints it walks to one after another and then from the start again, in its parent's
## space; empty: it stands where it's placed.
@export var route: PackedVector3Array = []
## Whether it sits where it's placed, for good: on the seat behind it (its feet where it's placed,
## see `humanoid.py`, sit()).
@export var seated: bool = false
## The waypoint of its `route` where it sits down for `sit_time` (on the seat behind it, facing
## `seat_yaw`) instead of the short stop; -1: none.
@export var seat_stop: int = -1
## Which way it faces sitting at its `seat_stop`: its yaw in its parent's space, in degrees (0: +z).
@export var seat_yaw: float = 0.0
## How long it sits at its `seat_stop`, in s (value TBD (playtest)).
@export var sit_time: float = 20.0

## The waypoint it walks to next.
var next: int = 0

var _stop_left: float = 0.0
var _remark: int = 0

@onready var body: NpcBody = $Body
@onready var bubble: WorldPanel = $Bubble


func _ready() -> void:
	if not route.is_empty():
		body.add_to_group(ShipDoor.OPENERS)
	body.tint = tint
	body.profile = profile
	if seated:
		body.sitting = true
		body.settle()
	bubble.visible = false
	# Only shows for a moment: over the walls and props in front of it.
	bubble.set_on_top(true)


func _physics_process(delta: float) -> void:
	_walk(delta, Player.nearest(get_tree(), global_position, NpcBody.NOTICE_RANGE) == null)
	_listen()


func _process(_delta: float) -> void:
	body.plate_allowed = not bubble.visible
	if bubble.visible:
		SpeechBubble.place(bubble, body.get_head_position(), SpeechBubble.view_scale(get_tree()))


## Whether it's walking right now.
func is_walking() -> bool:
	return not route.is_empty() and _stop_left <= 0.0 and body.is_walking()


## Whether it sits (or is sitting down) right now.
func is_sitting() -> bool:
	return body.sitting


## The remark showing in its bubble, or "" (translated).
func get_remark() -> String:
	var speech := bubble.content as SpeechBubble
	return speech.get_line() if speech and bubble.visible else ""


## Shows its next remark for a while.
func remark() -> void:
	if not profile or profile.remarks.is_empty():
		return
	var speech := bubble.content as SpeechBubble
	if speech:
		speech.show_line(tr(profile.remarks[_remark]))
	_remark = (_remark + 1) % profile.remarks.size()
	bubble.visible = true


## Walks on along the route while `free` (no player close), turning into the way it goes; at its
## seat stop it turns to the seat's way and sits until the stop is over, then gets up first.
func _walk(delta: float, free: bool) -> void:
	if route.is_empty():
		return
	if body.sitting and not seated:
		rotation.y = lerp_angle(rotation.y, deg_to_rad(seat_yaw), 1.0 - exp(-TURN_SPEED * delta))
	if not free:
		body.walk(0.0)
		return
	if _stop_left > 0.0:
		_stop_left -= delta
		body.walk(0.0)
		if _stop_left <= 0.0:
			body.sitting = false
		return
	if body.get_sit_amount() > 0.0:
		body.walk(0.0)  # getting up
		return
	var target: Vector3 = route[next]
	var offset := Vector3(target.x - position.x, 0.0, target.z - position.z)
	var step: float = WALK_SPEED * delta
	if offset.length() <= step:
		position = Vector3(target.x, position.y, target.z)
		body.sitting = next == seat_stop
		_stop_left = sit_time if body.sitting else STOP_TIME
		next = (next + 1) % route.size()
		body.walk(0.0)
		return
	var way: Vector3 = offset.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(way.x, way.z), 1.0 - exp(-TURN_SPEED * delta))
	position += way * step
	body.walk(WALK_SPEED)


## Says a remark to a player who stops close by, until every player has walked off.
func _listen() -> void:
	if bubble.visible:
		bubble.visible = Player.nearest(get_tree(), global_position, LEAVE_RANGE) != null
		return
	var near: Player = Player.nearest(get_tree(), global_position, REMARK_RANGE)
	if near and near.velocity.length() <= STILL_SPEED:
		remark()
