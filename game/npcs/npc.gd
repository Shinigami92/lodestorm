class_name Npc
extends Station
## A crew member aboard (see GAME_DESIGN.md, Spaceship: NPCs), who `profile` says, standing at
## their spot: their `Body` (an `NpcBody`: the look, turning towards players, the name plate) and
## an amber marker above their head while they have something the players haven't heard yet.
##
## Talking to them is a station (`interact`): the camera frames them and the player, their lines
## show in a speech bubble above their head (`Bubble`, a `SpeechBubble`), and the card beside
## them (a `TalkCard`) lists the open topics of their `Dialogue` or moves the topic on. Each line
## is also spoken from their head, in their recorded voice (`VoiceLines`, on the Voice bus), and
## stops when the next one comes; the prompt (one of theirs, picked for each talk) is spoken when
## the talk starts without the greeting. A guest aboard (a co-op player who isn't the host) hears a
## topic's guest lines where it has them (`Topic.lines_for`).
## The greeting plays by itself the first time. Up and down pick a topic, `interact` plays it (or
## the next line), `pause` steps back from a topic to the list and closes from there. What's been
## heard is a flag in the ship's `Story`.
## With "Continue by itself" on (`GameSettings.dialogue_auto_continue`), a topic's line moves on
## by itself: a voiced one `AUTO_PAUSE` s after the voice ends, one without a voice after its
## reading time (`reading_time`); after the last line the list comes back. The card's "Continue"
## fills up meanwhile; pressing it still moves on at once. Pausing it (the card's pause button, or
## `place_miner`) stops the wait and the voice in the middle of the line until it's resumed (the
## voice goes on where it stopped); moving on (a line, a topic, the list) plays normally again.
## They walk aboard instead of appearing somewhere (`NpcWalker`, over the ship's navigation): with
## a `flight_seat`, they walk there once a destination is chosen at the navigator, or once the ship
## flies (faster, `HURRY_SPEED`, stopping for nobody on the way), sit down and wait for the course
## or watch the autopilot, stay seated `SEAT_LINGER` s after it has landed
## or docked (a short flight that's over before they're there: they still sit down for that long),
## get up and walk back to their spot (at `WALK_SPEED`, stopping while a player is
## within `NpcBody.NOTICE_RANGE` m). While someone talks to them, they stay where they are.

## The camera's focus while talking: this far right on screen (in m) from between them and the
## player, at this height, so the card on their right stays in view.
const FOCUS_RIGHT: float = 0.35
const FOCUS_HEIGHT: float = 1.3
## How their voice carries: as loud as close by up to `VOICE_UNIT_SIZE` m, gone beyond
## `VOICE_MAX_DISTANCE` m. TBD (playtest).
const VOICE_UNIT_SIZE: float = 6.0
const VOICE_MAX_DISTANCE: float = 30.0
## Auto-continue: the pause after a voiced line ends, and how long a line without a voice stays
## (`READ_BASE` s plus `READ_PER_LETTER` s per letter of the shown text, a calm reading speed), in
## s. TBD (playtest).
const AUTO_PAUSE: float = 1.0
const READ_BASE: float = 2.0
const READ_PER_LETTER: float = 0.06
## Walking speed, and the one on the way to the `flight_seat`, in m/s. TBD (playtest).
const WALK_SPEED: float = 1.3
const HURRY_SPEED: float = 2.0
## Seconds they stay in the `flight_seat` once the ship has landed or docked. TBD (playtest).
const SEAT_LINGER: float = 5.0
## How fast they turn to face the way their spot or seat faces (per s, smoothed).
const TURN_SPEED: float = 5.0

## Who they are and what they talk about.
@export var profile: NpcProfile
## Where they sit while the ship flies (the seat's spot: their feet, facing the way it faces; the
## seat behind it, see `NpcBody.sitting`); none: they stay at their spot.
@export var flight_seat: Node3D

## The topic being told, or null while the card lists the topics.
var topic: Topic
## The line of `topic` shown.
var line: int = 0
## The highlighted entry of the list: an open topic (`get_choices`), or after them "Goodbye".
var choice: int = 0
## What they say while the list shows, this talk (the English text, see `Dialogue.pick_prompt`).
var prompt: String = ""
## Whether moving on by itself and the voice are paused (until resumed or the next line).
var auto_paused: bool = false
## Speaks their lines, from their head.
var voice: AudioStreamPlayer3D

## Used without a ship (e.g. tests of a lone NPC).
var _own_story := Story.new()
var _new_marker_time: float = 0.0
## How long the line shown waits before it moves on by itself (0: it doesn't), and for how long it
## has waited.
var _line_time: float = 0.0
var _line_waited: float = 0.0
## Their spot (where they stand in the scene).
var _home: Transform3D
## Whether they're on their way to the `flight_seat` or sitting there (from the flight's start
## until they've sat `SEAT_LINGER` s after it), and the seconds left to sit after the flight.
var _seat_trip: bool = false
var _linger: float = 0.0
var _walker: NpcWalker

@onready var bubble: WorldPanel = $Bubble
@onready var body: NpcBody = $Body
@onready var _new_marker: Node3D = $NewMarker


func _ready() -> void:
	super()
	_home = transform
	body.profile = profile
	_walker = NpcWalker.new(self, body)
	bubble.visible = false
	voice = AudioStreamPlayer3D.new()
	voice.name = "Voice"
	voice.bus = &"Voice"
	voice.unit_size = VOICE_UNIT_SIZE
	voice.max_distance = VOICE_MAX_DISTANCE
	voice.position = Vector3.UP * body.head_height
	add_child(voice)


func _physics_process(delta: float) -> void:
	_take_post(delta)


func _process(delta: float) -> void:
	super(delta)
	body.faces = user
	body.plate_allowed = not user
	_new_marker.visible = not user and has_news(_listener())
	if _new_marker.visible:
		_new_marker_time += delta
		_new_marker.rotation.y = _new_marker_time * 1.5
		_new_marker.position.y = body.head_height + 0.5 + 0.04 * sin(_new_marker_time * 3.0)
	if user:
		_place_bubble()
		_auto_continue(delta)


## The story the topics heard go into: the ship's.
func get_story() -> Story:
	return ship.story if ship else _own_story


## Their name and role, as the name plate shows them.
func get_plate_text() -> String:
	return body.get_plate_text()


## The topics open now for `listener` (the player talking to them when null), in the dialogue's
## order (see `Topic.is_open`).
func get_choices(listener: Player = null) -> Array[Topic]:
	var choices: Array[Topic] = []
	if not profile or not profile.dialogue:
		return choices
	if not listener:
		listener = user
	var story: Story = get_story()
	var reaches: Array[StringName] = get_reached_bodies()
	for listed: Topic in profile.dialogue.topics:
		if listed.is_open(listener, story, reaches):
			choices.append(listed)
	return choices


## The ids of the planets and moons the ship reaches now (for topics about them, see
## `Topic.requires_body`): none without a ship on a voyage.
func get_reached_bodies() -> Array[StringName]:
	var reaches: Array[StringName] = []
	var voyage: Voyage = ship.voyage if ship else null
	var system: StarSystem = voyage.settings.system if voyage and voyage.settings else null
	if not system:
		return reaches
	for place: CelestialBody in system.bodies:
		if place.kind != CelestialBody.Kind.STATION and place.is_reachable(ship.heat_shield.mk):
			reaches.append(place.id)
	return reaches


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
		var told: Array[String] = get_topic_lines()
		return tr(told[line]) if line < told.size() else ""
	return tr(prompt) if not prompt.is_empty() else ""


## The lines of the topic being told for the player talking to them (a guest's where it has them,
## see `Topic.lines_for`); none while the list shows.
func get_topic_lines() -> Array[String]:
	return topic.lines_for(is_guest()) if topic else ([] as Array[String])


## Whether the player talking to them is a guest aboard (in co-op, not the host): the ship and its
## decisions are the host's.
func is_guest() -> bool:
	return not multiplayer.is_server()


## How far the line shown is towards moving on by itself (0..1, also while paused), or -1 when it
## won't (no topic told, or auto-continue off).
func get_auto_progress() -> float:
	if not topic or _line_time <= 0.0 or not GameSettings.dialogue_auto_continue:
		return -1.0
	return clampf(_line_waited / _line_time, 0.0, 1.0)


## Pauses moving on by itself and the voice in the middle of the line, or resumes both from where
## they stopped (only while it applies, see `get_auto_progress`). Returns whether it did.
func toggle_auto_pause() -> bool:
	if get_auto_progress() < 0.0:
		return false
	_set_paused(not auto_paused)
	refresh()
	return true


## How long `text` (a shown line) stays when it moves on by itself without a voice, in s.
static func reading_time(text: String) -> float:
	return READ_BASE + READ_PER_LETTER * text.length()


## Starts telling `told` from its first line.
func talk_about(told: Topic) -> void:
	topic = told
	line = 0
	if get_topic_lines().is_empty():
		_finish_topic()
	_speak()
	_show()


## Shows the next line; after the last one the topic counts as heard and the list comes back.
func advance() -> void:
	if not topic:
		return
	line += 1
	if line >= get_topic_lines().size():
		_finish_topic()
	_speak()
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
	_set_paused(false)
	_show()
	voice.stop()
	return true


func get_look_target() -> Vector3:
	return body.global_position


func _back() -> bool:
	return leave_topic()


## `place_miner` pauses or resumes moving on by itself (see `toggle_auto_pause`).
func _shortcut(event: InputEvent) -> bool:
	return event.is_action_pressed(&"place_miner") and toggle_auto_pause()


func _opened() -> void:
	topic = null
	choice = 0
	_set_paused(false)
	if profile and profile.dialogue:
		prompt = profile.dialogue.pick_prompt(prompt)
	_place_focus()
	super()
	bubble.visible = true
	bubble.set_on_top(true)
	var greeting: Topic = profile.dialogue.greeting if profile and profile.dialogue else null
	if greeting and is_new(greeting):
		talk_about(greeting)
	else:
		_show()
		_say(prompt)
	_place_bubble()


func _closed() -> void:
	super()
	topic = null
	bubble.visible = false
	bubble.set_on_top(false)
	_set_paused(false)
	voice.stop()


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


## Speaks the topic's line shown, or stops when the list is back; starts the line's wait for
## moving on by itself (its voice and `AUTO_PAUSE`, else its `reading_time`).
func _speak() -> void:
	_set_paused(false)
	var lines: Array[String] = get_topic_lines()
	var told: bool = line < lines.size()
	var recording: AudioStream = _say(lines[line] if told else "")
	_line_waited = 0.0
	_line_time = 0.0
	if told:
		_line_time = (
			recording.get_length() + AUTO_PAUSE if recording else reading_time(get_line())
		)


## Pauses or resumes moving on by itself and the voice.
func _set_paused(paused: bool) -> void:
	auto_paused = paused
	voice.stream_paused = paused


## Speaks `english` (a line's English text) in their voice, stopping what they said before; just
## stops without a recording of it. Returns the recording, or null.
func _say(english: String) -> AudioStream:
	voice.stop()
	var recording: AudioStream = VoiceLines.stream(profile.id, english) if profile else null
	if recording:
		voice.stream = recording
		voice.play()
	return recording


## Moves the topic on by itself once the line shown has waited long enough (with auto-continue
## on, not paused), and shows how far it is on the card.
func _auto_continue(delta: float) -> void:
	if get_auto_progress() >= 0.0 and not auto_paused:
		_line_waited += delta
		if _line_waited >= _line_time:
			advance()
	var card_shown := card_menu as TalkCard
	if card_shown:
		card_shown.show_progress(get_auto_progress())


## Whether they're on their way somewhere (walking, or standing for a player in the way).
func is_underway() -> bool:
	return _walker.is_underway()


## Where they want to be now (in their parent's space): the `flight_seat` while a destination is
## chosen or the ship flies (until they've sat there `SEAT_LINGER` s after), else their spot.
func get_post() -> Transform3D:
	if not _wants_seat():
		return _home
	var parent: Node3D = get_parent_node_3d()
	return parent.global_transform.affine_inverse() * flight_seat.global_transform


## Walks to their post (`get_post`) and takes it: facing its way, sitting down at the seat; gets up
## first to leave the seat; stays put while someone talks to them.
func _take_post(delta: float) -> void:
	if ship and flight_seat:
		if ship.flight.is_flying() or _destination_chosen():
			_seat_trip = true
			_linger = SEAT_LINGER
		elif body.sitting and body.get_sit_amount() >= 1.0:
			_linger -= delta
			_seat_trip = _linger > 0.0
	if user:
		_walker.stop()
		return
	var post: Transform3D = get_post()
	var seat: bool = _wants_seat()
	if body.sitting and not seat:
		body.sitting = false
	if body.get_sit_amount() > 0.0 and not body.sitting:
		return  # getting up
	var hurry: bool = seat
	if not hurry and Player.nearest(get_tree(), global_position, NpcBody.NOTICE_RANGE):
		_walker.stop()
		return
	var navigation: ShipNavigation = ship.navigation if ship else null
	var speed: float = HURRY_SPEED if hurry else WALK_SPEED
	if not _walker.walk_to(post.origin, speed, navigation, delta):
		return
	var yaw: float = post.basis.get_euler().y
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-TURN_SPEED * delta))
	if seat and not body.sitting and absf(angle_difference(rotation.y, yaw)) < 0.05:
		body.sitting = true


## Whether a destination is chosen at the navigator that the ship isn't at or flying to yet.
func _destination_chosen() -> bool:
	var voyage: Voyage = ship.voyage if ship else null
	return voyage != null and voyage.destination != null and voyage.destination != voyage.brief


func _wants_seat() -> bool:
	return flight_seat != null and _seat_trip


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


func _place_bubble() -> void:
	SpeechBubble.place(bubble, body.get_head_position())
