class_name Npc
extends Station
## A crew member aboard (see GAME_DESIGN.md, Spaceship: NPCs), who `profile` says. Greybox: the
## suit model in a darker tint with the collar light in their own color, standing at their spot
## and turning towards the nearest player close by. Their name plate shows while a player is near,
## and an amber marker above their head while they have something the players haven't heard yet.
##
## Talking to them is a station (`interact`): the camera frames them and the player, their lines
## show in a speech bubble above their head (`Bubble`, a `SpeechBubble`), and the card beside
## them (a `TalkCard`) lists the open topics of their `Dialogue` or moves the topic on. The
## greeting plays by itself the first time. Up and down pick a topic, `interact` plays it (or the
## next line), `pause` steps back from a topic to the list and closes from there. What's been heard
## is a flag in the ship's `Story`.

## How close (in m) a player must be for them to turn towards them.
const NOTICE_RANGE: float = 3.0
## How close (in m) a player must be to see their name plate.
const PLATE_RANGE: float = 4.0
## How fast they turn (per s, smoothed).
const TURN_SPEED: float = 5.0
## Where the top of the head is, in m above their feet: the speech bubble sits above it.
const HEAD_HEIGHT: float = 1.9
## Gap between the head and the bubble's tail, in m.
const BUBBLE_GAP: float = 0.05
## The camera's focus while talking: this far right on screen (in m) from between them and the
## player, at this height, so the card on their right stays in view.
const FOCUS_RIGHT: float = 0.35
const FOCUS_HEIGHT: float = 1.3

## Who they are and what they talk about.
@export var profile: NpcProfile

## The ship whose story they follow; the one they stand in when not set.
var ship: Ship
## The topic being told, or null while the card lists the topics.
var topic: Topic
## The line of `topic` shown.
var line: int = 0
## The highlighted entry of the list: an open topic (`get_choices`), or after them "Goodbye".
var choice: int = 0

## Used without a ship (e.g. tests of a lone NPC).
var _own_story := Story.new()
var _new_marker_time: float = 0.0

@onready var bubble: WorldPanel = $Bubble
@onready var _body: Node3D = $Body
@onready var _model: Node3D = $Body/Model
@onready var _animator: PlayerAnimator = $Animator
@onready var _plate: Label3D = $NamePlate
@onready var _new_marker: Node3D = $NewMarker


func _ready() -> void:
	super()
	_animator.aiming = false
	_animator.setup(_model)
	_dress()
	bubble.visible = false
	_plate.visible = false


func _process(delta: float) -> void:
	super(delta)
	_turn(delta)
	var near: Player = Player.nearest(get_tree(), global_position, PLATE_RANGE)
	_plate.visible = near != null and not user
	if _plate.visible:
		_plate.text = get_plate_text()
	_new_marker.visible = not user and has_news(_listener())
	if _new_marker.visible:
		_new_marker_time += delta
		_new_marker.rotation.y = _new_marker_time * 1.5
		_new_marker.position.y = HEAD_HEIGHT + 0.5 + 0.04 * sin(_new_marker_time * 3.0)
	if user:
		_place_bubble()


## The story the topics heard go into: the ship's.
func get_story() -> Story:
	# The ship joins its group when it's ready, after its rooms.
	if not ship:
		ship = Ship.nearest(get_tree(), global_position)
	return ship.story if ship else _own_story


## Their name and role, as the name plate shows them.
func get_plate_text() -> String:
	if not profile:
		return ""
	return "%s · %s" % [profile.display_name, tr(profile.role)]


## The topics open now for `listener` (the player talking to them when null), in the dialogue's
## order: their story flags are set, and `listener` owns the weapon a topic is about.
func get_choices(listener: Player = null) -> Array[Topic]:
	var choices: Array[Topic] = []
	if not profile or not profile.dialogue:
		return choices
	if not listener:
		listener = user
	var story: Story = get_story()
	for listed: Topic in profile.dialogue.topics:
		if not story.is_set_all(listed.requires):
			continue
		if (
			listed.requires_weapon
			and not (listener and listener.arsenal.owns(listed.requires_weapon))
		):
			continue
		choices.append(listed)
	return choices


## Whether nobody has heard `listed` to the end yet.
func is_new(listed: Topic) -> bool:
	return not get_story().is_set(listed.id)


## Whether they have something nobody has heard yet for `listener` (the greeting or an open
## topic; the player talking to them when null).
func has_news(listener: Player = null) -> bool:
	if not profile or not profile.dialogue:
		return false
	var greeting: Topic = profile.dialogue.greeting
	if greeting and is_new(greeting):
		return true
	return get_choices(listener).any(is_new)


## What their bubble says now (translated): the topic's line, or the prompt while listing.
func get_line() -> String:
	if topic:
		return tr(topic.lines[line]) if line < topic.lines.size() else ""
	return tr(profile.dialogue.prompt) if profile and profile.dialogue else ""


## Starts telling `told` from its first line.
func talk_about(told: Topic) -> void:
	topic = told
	line = 0
	if topic.lines.is_empty():
		_finish_topic()
	_show()


## Shows the next line; after the last one the topic counts as heard and the list comes back.
func advance() -> void:
	if not topic:
		return
	line += 1
	if line >= topic.lines.size():
		_finish_topic()
	_show()


## Does what `interact` does: the next line of the topic, or the highlighted list entry (a topic,
## or "Goodbye", which closes).
func press() -> void:
	if topic:
		advance()
		return
	var choices: Array[Topic] = get_choices()
	if choice < choices.size():
		talk_about(choices[choice])
	else:
		close()


## Highlights list entry `index` (an open topic, or after them "Goodbye").
func set_choice(index: int) -> void:
	choice = clampi(index, 0, get_choices().size())
	_show()


## Up and down move the highlight through the list (left and right do nothing here).
func step(direction: Vector2) -> void:
	if topic or is_zero_approx(direction.y):
		return
	var count: int = get_choices().size() + 1
	set_choice(posmod(choice + int(signf(direction.y)), count))


## Leaves the topic being told for the list (`pause`, "Back"). Returns whether one was told.
func leave_topic() -> bool:
	if not topic:
		return false
	topic = null
	_show()
	return true


func get_look_target() -> Vector3:
	return _body.global_position


func _back() -> bool:
	return leave_topic()


func _opened() -> void:
	topic = null
	choice = 0
	_place_focus()
	super()
	bubble.visible = true
	bubble.set_on_top(true)
	var greeting: Topic = profile.dialogue.greeting if profile and profile.dialogue else null
	if greeting and is_new(greeting):
		talk_about(greeting)
	else:
		_show()
	_place_bubble()


func _closed() -> void:
	super()
	topic = null
	bubble.visible = false
	bubble.set_on_top(false)


func _finish_topic() -> void:
	get_story().set_flag(topic.id)
	topic = null
	choice = mini(choice, get_choices().size())


## Shows the current state on the card and in the bubble.
func _show() -> void:
	refresh()
	var speech := bubble.content as SpeechBubble
	if speech:
		speech.show_line(get_line())


## Who the "something new" marker is for: the player talking to them, else the nearest one.
func _listener() -> Player:
	return user if user else Player.nearest(get_tree(), global_position, INF)


## Puts the camera's focus between them and the player talking to them (where they stand), a
## little to the right on screen (see `FOCUS_RIGHT`); unchanged without a camera.
func _place_focus() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera or not view_focus or not user:
		return
	var right := Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z)
	if right.is_zero_approx():
		return
	var between: Vector3 = global_position.lerp(user.global_position, 0.5)
	between.y = global_position.y
	view_focus.global_position = (
		between + right.normalized() * FOCUS_RIGHT + Vector3.UP * FOCUS_HEIGHT
	)


## Keeps the bubble above the head, facing the camera.
func _place_bubble() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return
	var view: Basis = camera.global_basis.orthonormalized()
	var head: Vector3 = _body.global_position + Vector3.UP * HEAD_HEIGHT
	bubble.global_transform = Transform3D(view, head + view.y * (bubble.size.y * 0.5 + BUBBLE_GAP))


## Turns the body towards the player talking to them, else the nearest one close by, else back to
## where they stand facing.
func _turn(delta: float) -> void:
	var target: Player = user if user else Player.nearest(get_tree(), global_position, NOTICE_RANGE)
	var yaw: float = 0.0
	if target:
		var to_target: Vector3 = global_basis.inverse() * (target.global_position - global_position)
		if Vector2(to_target.x, to_target.z).length() > 0.1:
			yaw = atan2(to_target.x, to_target.z)
	_body.rotation.y = lerp_angle(_body.rotation.y, yaw, 1.0 - exp(-TURN_SPEED * delta))


## The suit in the crew's darker tint, the collar light in their own color.
func _dress() -> void:
	if not profile:
		return
	var suit := _model.find_child("Suit") as MeshInstance3D
	if suit and suit.mesh:
		for surface: int in suit.mesh.get_surface_count():
			var material := suit.get_active_material(surface) as BaseMaterial3D
			if not material:
				continue
			var tinted := material.duplicate() as BaseMaterial3D
			tinted.albedo_color *= profile.suit_tint
			suit.set_surface_override_material(surface, tinted)
	var band := _model.find_child("SuitLight") as GeometryInstance3D
	if band:
		var light := StandardMaterial3D.new()
		light.albedo_color = profile.accent_color
		light.emission_enabled = true
		light.emission = profile.accent_color
		light.emission_energy_multiplier = 2.0
		band.material_override = light
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
