class_name Npc
extends Station
## A crew member aboard (see docs/design/crew.md), who `profile` says, standing at
## their spot: their `Body` (an `NpcBody`: the look, turning towards players, the name plate) and
## an amber marker above their head: round while they have something the players haven't heard
## yet, a diamond while they offer a quest or a quest step can be handed in at them
## (`has_quest_news`).
##
## Talking to them is a station (`interact`): the camera frames them and the player, their lines
## show in a speech bubble above their head (`Bubble`, a `SpeechBubble`), and the card beside
## them (a `TalkCard`) lists the open topics of their `Dialogue` (`get_choices`) or moves the
## topic on: their `talk` (an `NpcTalk`). Their quests (`get_quests`, the ship's `QuestLog`) join
## the list first: a quest they offer (its `Quest.offer`) and a step handed in at them (its
## `QuestStep.hand_in`). Each line is also spoken from their head, in their
## recorded voice (`say`: `VoiceLines`, on the Voice bus), and stops when the next one comes.
## Where they are and go aboard is their `routine` (an `NpcRoutine`: walking, the `flight_seat`
## while the ship flies, their `work_spots`, a tour).
## With a `Tour` (their profile's), their first talk while they wait at its start is its offer
## instead of their greeting, its invite ("Show me the ship") is among their topics once the offer
## is heard and starts the tour when heard to the end (the talk closes); during the tour the card
## offers only going on and ending it. A tour's stops are said aside (`say_aside`): in the bubble
## above their head without a talk, and in their voice.

## The camera's focus while talking: this far right on screen (in m) from between them and the
## player, at this height, so the card on their right stays in view.
const FOCUS_RIGHT: float = 0.35
const FOCUS_HEIGHT: float = 1.3
## How their voice carries: as loud as close by up to `VOICE_UNIT_SIZE` m, gone beyond
## `VOICE_MAX_DISTANCE` m. TBD (playtest).
const VOICE_UNIT_SIZE: float = 6.0
const VOICE_MAX_DISTANCE: float = 30.0

## Who they are and what they talk about.
@export var profile: NpcProfile
## Where they sit while the ship flies (the seat's spot: their feet, facing the way it faces; the
## seat behind it, see `NpcBody.sitting`); none: they stay at their spot.
@export var flight_seat: Node3D
## Where else they work now and then (none: always at their spot).
@export var work_spots: Array[WorkSpot] = []
## What they do at their own spot when they have work spots; none: `NpcRoutine.HOME_ACTIVITIES`.
@export var home_activities: Array[StringName] = []

## Speaks their lines, from their head.
var voice: AudioStreamPlayer3D
## The talk while a player talks to them.
var talk: NpcTalk
## Where they are and go aboard.
var routine: NpcRoutine

## Used without a ship (e.g. tests of a lone NPC).
var _own_story := Story.new()
var _own_quests := QuestLog.new()
## Whether the bubble shows a line said aside (`say_aside`), not a talk.
var _aside: bool = false
var _new_marker_time: float = 0.0

@onready var bubble: WorldPanel = $Bubble
@onready var body: NpcBody = $Body
@onready var _new_marker: Node3D = $NewMarker
@onready var _quest_marker: Node3D = $NewMarker/Diamond
@onready var _news_marker: Node3D = $NewMarker/Round


func _ready() -> void:
	super()
	body.profile = profile
	_own_quests.story = _own_story
	routine = NpcRoutine.new(self)
	talk = NpcTalk.new(self)
	bubble.visible = false
	voice = AudioStreamPlayer3D.new()
	voice.name = "Voice"
	voice.bus = &"Voice"
	voice.unit_size = VOICE_UNIT_SIZE
	voice.max_distance = VOICE_MAX_DISTANCE
	voice.position = Vector3.UP * body.head_height
	add_child(voice)


func _physics_process(delta: float) -> void:
	routine.update(delta)


func _process(delta: float) -> void:
	super(delta)
	body.faces = user
	body.plate_allowed = not user and not _aside
	var quest_news: bool = not user and has_quest_news(_listener())
	_new_marker.visible = quest_news or (not user and has_news(_listener()))
	_quest_marker.visible = quest_news
	_news_marker.visible = not quest_news
	if _new_marker.visible:
		_new_marker_time += delta
		_new_marker.rotation.y = _new_marker_time * 1.5
		_new_marker.position.y = body.head_height + 0.5 + 0.04 * sin(_new_marker_time * 3.0)
	if user:
		_place_bubble()
		talk.update(delta)
	elif _aside:
		SpeechBubble.place(bubble, body.get_head_position(), SpeechBubble.view_scale(get_tree()))


## The story the topics heard go into: the ship's.
func get_story() -> Story:
	return ship.story if ship else _own_story


## Their name and role, as the name plate shows them.
func get_plate_text() -> String:
	return body.get_plate_text()


## The quests the topics heard and handed in go into: the ship's.
func get_quests() -> QuestLog:
	return ship.quests if ship else _own_quests


## The topics open now for `listener` (the player talking to them when null): their quests' first
## (the offers, then the steps handed in at them), then the dialogue's in its order (see
## `Topic.is_open`).
func get_choices(listener: Player = null) -> Array[Topic]:
	var choices: Array[Topic] = []
	if not profile or not profile.dialogue:
		return choices
	if not listener:
		listener = user
	var story: Story = get_story()
	var tour: Tour = profile.tour
	if tour and routine and routine.tour:
		choices.append_array([tour.resume, tour.abort])
		return choices
	var reaches: Array[StringName] = get_reached_bodies()
	var quests: QuestLog = get_quests()
	for quest: Quest in quests.offered_by(profile.id, reaches):
		choices.append(quest.offer)
	for quest: Quest in quests.steps_at(profile.id):
		choices.append(quests.current_step(quest).hand_in)
	for listed: Topic in profile.dialogue.topics:
		if listed.is_open(listener, story, reaches):
			choices.append(listed)
	if tour and tour.invite.is_open(listener, story):
		choices.append(tour.invite)
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


## Whether nobody has heard `listed` to the end yet; for a quest step's hand-in, whether `listener`
## (the player talking to them when null) can hand it in now.
func is_new(listed: Topic, listener: Player = null) -> bool:
	var quests: QuestLog = get_quests()
	var quest: Quest = quests.quest_for(listed)
	if quest and quests.is_accepted(quest):
		var payer: Player = listener if listener else user
		return payer != null and quests.can_hand_in(quest, payer.hold)
	return not get_story().is_set(listed.id)


## Whether they have something nobody has heard yet for `listener` (the greeting or an open
## topic; the player talking to them when null).
func has_news(listener: Player = null) -> bool:
	if not profile or not profile.dialogue:
		return false
	var greeting: Topic = get_greeting()
	if greeting and is_new(greeting):
		return true
	return get_choices(listener).any(func(listed: Topic) -> bool: return is_new(listed, listener))


## Whether they offer `listener` (the player talking to them when null) a quest, or `listener` can
## hand in a quest step at them now (the diamond marker).
func has_quest_news(listener: Player = null) -> bool:
	if not profile or (routine and routine.tour):
		return false
	var quests: QuestLog = get_quests()
	if not quests.offered_by(profile.id, get_reached_bodies()).is_empty():
		return true
	var payer: Player = listener if listener else user
	return (
		payer != null
		and quests.steps_at(profile.id).any(
			func(quest: Quest) -> bool: return quests.can_hand_in(quest, payer.hold)
		)
	)


## The greeting their first talk starts with: their tour's offer while they wait at its start,
## else their dialogue's.
func get_greeting() -> Topic:
	if routine and routine.is_waiting():
		return profile.tour.offer
	return profile.dialogue.greeting if profile and profile.dialogue else null


## Whether the player talking to them is a guest aboard (in co-op, not the host): the ship and its
## decisions are the host's.
func is_guest() -> bool:
	return not multiplayer.is_server()


## Up and down move the highlight through the talk's list (see `NpcTalk.step`).
func step(direction: Vector2) -> void:
	talk.step(direction)


func get_look_target() -> Vector3:
	return body.global_position


## Says `english` (a line's English text) aside, without a talk: in the bubble above their head
## and in their voice; "" stops and hides it. Returns how long it stays (`VoiceLines.stay_time`).
func say_aside(english: String) -> float:
	if user:
		return 0.0
	var recording: AudioStream = say(english)
	_aside = not english.is_empty()
	bubble.visible = _aside
	bubble.set_on_top(_aside)
	if not _aside:
		return 0.0
	var speech := bubble.content as SpeechBubble
	if speech:
		speech.show_line(tr(english))
	return VoiceLines.stay_time(recording, tr(english))


## Speaks `english` (a line's English text) in their voice, stopping what they said before; just
## stops without a recording of it. Returns the recording, or null.
func say(english: String) -> AudioStream:
	voice.stop()
	var recording: AudioStream = VoiceLines.stream(profile.id, english) if profile else null
	if recording:
		voice.stream = recording
		voice.play()
	return recording


func _back() -> bool:
	return talk.leave_topic()


## `place_miner` pauses or resumes moving on by itself (see `NpcTalk.toggle_auto_pause`).
func _shortcut(event: InputEvent) -> bool:
	return event.is_action_pressed(&"place_miner") and talk.toggle_auto_pause()


func _opened() -> void:
	talk.open()
	_place_focus()
	super()
	_aside = false
	bubble.visible = true
	bubble.set_on_top(true)
	talk.greet()
	_place_bubble()


func _closed() -> void:
	super()
	talk.close()
	bubble.visible = false
	bubble.set_on_top(false)


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
