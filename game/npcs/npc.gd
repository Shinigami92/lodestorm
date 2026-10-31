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
## above their head without a talk, and in their voice. So are an overheard talk's lines
## (`OverheardTalks`), and while it plays (`overheard`) nobody can talk to them.
## A crew member who joins later (`NpcProfile.join_flag`) isn't there until they're aboard
## (`is_present`): hidden, still and nobody can talk to them. Until then they wait at their place
## (a second NPC of their profile there, `waits_to_join`, e.g. Dace at his stall at Ostra), and once
## they join, that one walks aboard (`NpcBoarding`) and theirs aboard takes over at the door
## (`arrive`), walking on to their post. There they're talked to only about what fits before
## joining: the topics that go once they join (`Topic.until` their `NpcProfile.join_flag`) and their
## quests, no greeting. Someone waiting out in a location (e.g. Hollis at his camp, see
## `LocationQuests`) sees the quests as they are out there (`quests_view`); talking to them there
## stops the game solo (`pausing`, like the pause panel: aliens, the timer, the storm), so nobody is
## hurt meanwhile, and it goes on once the talk ends. In co-op the others cover them.

## Emitted when they set off for the ship from their place before joining (by `NpcBoarding`).
@warning_ignore("unused_signal")
signal walks_aboard

## Every crew member (the ship cuts them away by the deck they stand on, see `Ship`).
const CREW_GROUP: StringName = &"crew"
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
## Whether they sit at their own spot (on the seat behind it, like at the `flight_seat`), e.g. on a
## booth's bench.
@export var seated: bool = false
## Whether this is a crew member's place before they join (`NpcProfile.join_flag`): there until
## the flag is set, then walking aboard (`NpcBoarding`), gone once through the door. Talked to there
## only while they have something to say before joining (`get_choices`).
@export var waits_to_join: bool = false

## Speaks their lines, from their head.
var voice: AudioStreamPlayer3D
## The talk while a player talks to them.
var talk: NpcTalk
## Where they are and go aboard.
var routine: NpcRoutine
## The quests as they see them where they stand (out in a location, a `VisitQuests`); null: the
## ship's.
var quests_view: QuestLog
## Whether an overheard talk of theirs plays (see `OverheardTalks`): they stay put, facing the
## other, and can't be talked to; no name plate or marker meanwhile.
var overheard: bool = false:
	set(value):
		overheard = value
		_update_use()

## Used without a ship (e.g. tests of a lone NPC).
var _own_story := Story.new()
var _own_quests := QuestLog.new()
## Whether the bubble shows a line said aside (`say_aside`), not a talk.
var _aside: bool = false
## At their place before joining: whether they've joined (walking aboard or gone).
var _joined: bool = false
## Whether a talk out in a location stopped the game (solo).
var _pausing: bool = false
var _new_marker_time: float = 0.0

@onready var bubble: WorldPanel = $Bubble
@onready var body: NpcBody = $Body
@onready var _new_marker: Node3D = $NewMarker
@onready var _quest_marker: Node3D = $NewMarker/Diamond
@onready var _news_marker: Node3D = $NewMarker/Round


func _ready() -> void:
	super()
	add_to_group(CREW_GROUP)
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
	# The ship joins its group after its rooms are ready: its story is found a frame later.
	_watch_story.call_deferred()


func _physics_process(delta: float) -> void:
	routine.update(delta)


func _process(delta: float) -> void:
	super(delta)
	body.faces = user
	body.holds_facing = overheard
	# No plate or marker under a bubble: theirs or, in an overheard talk, the other one's.
	var free: bool = not user and not _aside and not overheard
	body.plate_allowed = free
	var quest_news: bool = free and has_quest_news(_listener())
	_new_marker.visible = quest_news or (free and has_news(_listener()))
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


## Whether they're here: a crew member once they're aboard (`NpcProfile.is_aboard`) and not on
## their way aboard any more (`NpcBoarding.is_walking`); at their place before joining
## (`waits_to_join`), until they join and while they walk aboard; anyone else always.
func is_present() -> bool:
	if not profile:
		return true
	if waits_to_join:
		return not profile.is_aboard(get_story()) or (routine != null and routine.boarding != null)
	if not profile.station.is_empty():
		return true
	return profile.is_aboard(get_story()) and not NpcBoarding.is_walking(get_tree(), profile.id)


## Their name and role, as the name plate shows them.
func get_plate_text() -> String:
	return body.get_plate_text()


## The quests the topics heard and handed in go into: the ship's (as seen from where they stand,
## `quests_view`).
func get_quests() -> QuestLog:
	if quests_view:
		return quests_view
	return ship.quests if ship else _own_quests


## The topics open now for `listener` (the player talking to them when null): their quests' first
## (the offers, then the steps handed in at them), then the dialogue's in its order (see
## `Topic.is_open`; at their place before joining, only those that go once they join).
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
	for quest: Quest in quests.offered_by(profile.id, reaches, profile.open_requests):
		choices.append(quest.offer)
	for quest: Quest in quests.steps_at(profile.id):
		choices.append(quests.current_step(quest).hand_in)
	for listed: Topic in profile.dialogue.topics:
		if waits_to_join and listed.until != profile.join_flag:
			continue
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
	if not profile or not profile.dialogue or (waits_to_join and not _talks_here()):
		return false
	var greeting: Topic = get_greeting()
	if greeting and is_new(greeting):
		return true
	return get_choices(listener).any(func(listed: Topic) -> bool: return is_new(listed, listener))


## Whether they offer `listener` (the player talking to them when null) a quest, or `listener` can
## hand in a quest step at them now (the diamond marker).
func has_quest_news(listener: Player = null) -> bool:
	if not profile or (waits_to_join and not _talks_here()) or (routine and routine.tour):
		return false
	var quests: QuestLog = get_quests()
	if not quests.offered_by(profile.id, get_reached_bodies(), profile.open_requests).is_empty():
		return true
	var payer: Player = listener if listener else user
	return (
		payer != null
		and quests.steps_at(profile.id).any(
			func(quest: Quest) -> bool: return quests.can_hand_in(quest, payer.hold)
		)
	)


## The greeting their first talk starts with: their tour's offer while they wait at its start,
## else their dialogue's; none at their place before joining.
func get_greeting() -> Topic:
	if waits_to_join:
		return null
	if routine and routine.is_waiting():
		return profile.tour.offer
	return profile.dialogue.greeting if profile and profile.dialogue else null


## Whether `player` may talk to them: not while an overheard talk of theirs plays.
func can_use(_player: Player) -> bool:
	return not overheard


## Whether the player talking to them is a guest aboard (in co-op, not the host): the ship and its
## decisions are the host's.
func is_guest() -> bool:
	return not multiplayer.is_server()


## Up and down move the highlight through the talk's list (see `NpcTalk.step`).
func step(direction: Vector2) -> void:
	talk.step(direction)


func get_look_target() -> Vector3:
	return body.global_position


## Comes aboard at `at` (global, inside the ramp's door; from their place before joining, see
## `NpcBoarding`) and walks on from there to their post.
func arrive(at: Transform3D) -> void:
	global_transform = at
	reset_physics_interpolation()
	routine.arrive()
	update_presence()


## Shows them and lets them move while they're here (`is_present`), else hides and stills them; at
## their place before joining, they start walking aboard once they join, and stop if that's taken
## back (a lost run).
func update_presence() -> void:
	var aboard: bool = profile.is_aboard(get_story()) if profile else true
	if waits_to_join and not _joined and aboard:
		_joined = true
		routine.start_boarding()
	elif waits_to_join and _joined and not aboard:
		_joined = false
		routine.stop_boarding()
	var present: bool = is_present()
	visible = present
	process_mode = PROCESS_MODE_INHERIT if present else PROCESS_MODE_DISABLED
	_update_use()


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
	_set_pausing(SaveGame.is_solo(get_tree()) and _is_out_there())
	talk.open()
	_place_focus()
	super()
	_aside = false
	bubble.visible = true
	bubble.set_on_top(true)
	talk.greet()
	_place_bubble()


func _closed() -> void:
	_set_pausing(false)
	super()
	_update_use()
	talk.close()
	bubble.visible = false
	bubble.set_on_top(false)


## Follows the story for whether they're here (`is_present`); at their place before joining, one
## who joined already (a save) is gone from it.
func _watch_story() -> void:
	var story: Story = get_story()
	_joined = waits_to_join and profile.is_aboard(story)
	story.changed.connect(update_presence)
	update_presence()


## Lets players talk to them while they're here (at their place before joining, while they have
## something to say there), nobody talks to them yet and no overheard talk of theirs plays.
func _update_use() -> void:
	if use_point:
		var here: bool = not waits_to_join or _talks_here()
		use_point.enabled = is_present() and here and not user and not overheard


## At their place before joining: whether they have something to say there (a topic that goes once
## they join, or quests as seen out there).
func _talks_here() -> bool:
	if quests_view:
		return true
	var topics: Array[Topic] = profile.dialogue.topics if profile and profile.dialogue else []
	var flag: StringName = profile.join_flag if profile else &""
	return (
		not flag.is_empty() and topics.any(func(listed: Topic) -> bool: return listed.until == flag)
	)


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


func _exit_tree() -> void:
	# Never leaves the game stopped (e.g. the location goes away).
	_set_pausing(false)


## Stops the game (`paused`) or lets it go on; while stopped, they and their talk keep going.
func _set_pausing(paused: bool) -> void:
	if _pausing == paused or not is_inside_tree():
		return
	_pausing = paused
	get_tree().paused = paused
	process_mode = PROCESS_MODE_ALWAYS if paused else PROCESS_MODE_INHERIT


## Whether they stand out in a generated location (not aboard or at a station).
func _is_out_there() -> bool:
	var at: Node = get_parent()
	while at:
		if at is GeneratedLocation:
			return true
		at = at.get_parent()
	return false
