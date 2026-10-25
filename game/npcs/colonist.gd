class_name Colonist
extends Node3D
## One of a station's ambient colonists (see GAME_DESIGN.md, Stations and outposts): the
## `NpcBody` that `profile` says (a role on the plate, no name), standing at its spot or walking
## its `route` round and round, with a short stop at every waypoint. It stops while a player is
## close (turning towards them, like the crew) instead of walking into them. When a player stops
## next to it, it says one of its profile's `remarks` in a speech bubble, which stays until they
## walk off; the next one comes when a player comes back. The bubble grows with the camera's view,
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


## Walks on along the route while `free` (no player close), turning into the way it goes.
func _walk(delta: float, free: bool) -> void:
	if route.is_empty() or not free:
		body.walk(0.0)
		return
	if _stop_left > 0.0:
		_stop_left -= delta
		body.walk(0.0)
		return
	var target: Vector3 = route[next]
	var offset := Vector3(target.x - position.x, 0.0, target.z - position.z)
	var step: float = WALK_SPEED * delta
	if offset.length() <= step:
		position = Vector3(target.x, position.y, target.z)
		next = (next + 1) % route.size()
		_stop_left = STOP_TIME
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
