class_name Colonist
extends Node3D
## One of a station's ambient colonists (see GAME_DESIGN.md, Stations and outposts): the
## `NpcBody` that `profile` says (a role on the plate, no name), standing at its spot or walking
## its `route` round and round, with a short stop at every waypoint. It stops while a player is
## close (turning towards them, like the crew) instead of walking into them. When a player stops
## next to it, it says one of its profile's `remarks` in a speech bubble for a while; the next one
## comes once that player has walked off and come back. The bubble grows with the camera's view,
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
## How long a remark shows, in s.
const REMARK_TIME: float = 4.0
## The camera's visible height (in m) the bubble is sized for: the view while talking to the crew
## (`Npc`'s `view_height`). Wider views scale it up.
const BUBBLE_VIEW_HEIGHT: float = 3.2

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
var _remark_left: float = 0.0
## Whether it has said a remark to the player close by (cleared once nobody is).
var _remarked: bool = false

@onready var body: NpcBody = $Body
@onready var bubble: WorldPanel = $Bubble


func _ready() -> void:
	body.tint = tint
	body.profile = profile
	bubble.visible = false
	# Only shows for a moment: over the walls and props in front of it.
	bubble.set_on_top(true)


func _physics_process(delta: float) -> void:
	_walk(delta, Player.nearest(get_tree(), global_position, NpcBody.NOTICE_RANGE) == null)
	_listen(delta)


func _process(_delta: float) -> void:
	body.plate_allowed = not bubble.visible
	if bubble.visible:
		SpeechBubble.place(bubble, body.get_head_position(), _bubble_scale())


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
	_remark_left = REMARK_TIME
	_remarked = true
	bubble.visible = true


## How much bigger the bubble shows than its size: the camera's visible height now over
## `BUBBLE_VIEW_HEIGHT` (1 without a camera rig).
func _bubble_scale() -> float:
	var rig := get_tree().get_first_node_in_group(IsoCameraRig.GROUP) as IsoCameraRig
	return rig.view_height() * rig.zoom / BUBBLE_VIEW_HEIGHT if rig else 1.0


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


## Says a remark to a player who stops close by (once until they leave), and hides it after a
## while.
func _listen(delta: float) -> void:
	if _remark_left > 0.0:
		_remark_left -= delta
		if _remark_left <= 0.0:
			bubble.visible = false
	var near: Player = Player.nearest(get_tree(), global_position, REMARK_RANGE)
	if not near:
		_remarked = false
		return
	if not _remarked and near.velocity.length() <= STILL_SPEED:
		remark()
