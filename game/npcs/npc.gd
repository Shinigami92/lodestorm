class_name Npc
extends Station
## A crew member aboard (see docs/design/crew.md), who `profile` says, standing at
## their spot: their `Body` (an `NpcBody`: the look, turning towards players, the name plate) and
## an amber marker above their head: round while they have something the players haven't heard
## yet, a diamond while they offer a quest or a quest step can be handed in at them
## (`NpcQuests.has_news`).
##
## Talking to them is a station (`interact`): the camera frames them and the player, their lines
## show in a speech bubble above their head (`Bubble`, a `SpeechBubble`), and the card beside
## them (a `TalkCard`) lists the open topics of their `Dialogue` (`get_choices`) or moves the
## topic on: their `talk` (an `NpcTalk`). Their `quests` (an `NpcQuests`, the ship's `QuestLog`)
## join the list first: a quest they offer (its `Quest.offer`) and a step handed in at them (its
## `QuestStep.hand_in`). Each line is also spoken from their head, in their
## recorded voice (`say`: `VoiceLines`, on the Voice bus), and stops when the next one comes.
## Where they are and go aboard is their `routine` (an `NpcRoutine`: walking, the `flight_seat`
## while the ship flies, their `work_spots`, a tour).
## With a `Tour` (their profile's), their first talk while they wait at its start is its offer
## instead of their greeting, its invite ("Show me the ship") is among their topics once the offer
## is heard and starts the tour when heard to the end (the talk closes); during the tour the card
## offers only going on and ending it (no greeting). A tour's stops are said aside (`say_aside`):
## in the bubble above their head without a talk, and in their voice. So are an overheard talk's
## lines (`OverheardTalks`), and while it plays (`overheard`) nobody can talk to them.
## A crew member who joins later (`NpcProfile.join_flag`) isn't there until they're aboard (their
## `presence`, an `NpcPresence`): hidden, still and nobody can talk to them. Until then they wait at
## their place (a second NPC of their profile there, `waits_to_join`, e.g. Dace at his stall at
## Ostra), and once they join, that one walks aboard (`NpcBoarding`) and theirs aboard takes over at
## the door (`NpcPresence.arrive`), walking on to their post. There they're talked to only about
## what fits before joining: the topics that go once they join (`Topic.until` their
## `NpcProfile.join_flag`) and their quests, no greeting. Someone waiting out in a location (e.g.
## Hollis at his camp, see `LocationQuests`) sees the quests as they are out there (`quests_view`);
## talking to them there stops the game solo (`GamePause`, like the pause panel: aliens, the timer,
## the storm), so nobody is hurt meanwhile, and it goes on once the talk ends. In co-op the others
## cover them.

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
## Whether they set course themselves once seated at the `flight_seat` (the pilot); others there
## only sit while the ship flies.
@export var sets_course: bool = false
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
## Their quests: the log, the entries at the top of their list, the diamond.
var quests: NpcQuests
## Whether they're here (one who joins later, their place before joining).
var presence: NpcPresence
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
## Whether the bubble shows a line said aside (`say_aside`), not a talk.
var _aside: bool = false
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
	routine = NpcRoutine.new(self)
	talk = NpcTalk.new(self)
	quests = NpcQuests.new(self, _own_story)
	presence = NpcPresence.new(self)
	presence.changed.connect(_on_presence_changed)
	bubble.visible = false
	voice = AudioStreamPlayer3D.new()
	voice.name = "Voice"
	voice.bus = &"Voice"
	voice.unit_size = VOICE_UNIT_SIZE
	voice.max_distance = VOICE_MAX_DISTANCE
	voice.position = Vector3.UP * body.head_height
	add_child(voice)
	# The ship joins its group after its rooms are ready: its story is found a frame later.
	presence.start.call_deferred()


func _physics_process(delta: float) -> void:
	routine.update(delta)


func _process(delta: float) -> void:
	super(delta)
	body.faces = user
	body.holds_facing = overheard
	# No plate or marker under a bubble: theirs or, in an overheard talk, the other one's.
	var free: bool = not user and not _aside and not overheard
	body.plate_allowed = free
	var quest_news: bool = free and quests.has_news(_listener())
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


## Their name and role, as the name plate shows them.
func get_plate_text() -> String:
	return body.get_plate_text()


## The topics open now for `listener` (the player talking to them when null): their quests' first
## (`NpcQuests.get_choices`), then the dialogue's in its order (see `Topic.is_open`; at their place
## before joining, only those that go once they join).
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
	var reaches: Array[StringName] = quests.reached_bodies()
	choices.append_array(quests.get_choices(listener))
	var replaced: Array[StringName] = quests.replaced_topics()
	for listed: Topic in profile.dialogue.topics:
		if (waits_to_join and listed.until != profile.join_flag) or listed.id in replaced:
			continue
		if listed.is_open(listener, story, reaches):
			choices.append(listed)
	# Also when they stopped waiting before its offer was heard (see `NpcRoutine.is_waiting`).
	if tour and (tour.invite.is_open(listener, story) or (routine and not routine.is_waiting())):
		choices.append(tour.invite)
	return choices


## Whether nobody has heard `listed` to the end yet; for a quest step's hand-in, whether `listener`
## (the player talking to them when null) can hand it in now.
func is_new(listed: Topic, listener: Player = null) -> bool:
	var quest_log: QuestLog = quests.get_log()
	var quest: Quest = quest_log.quest_for(listed)
	if quest and quest_log.is_accepted(quest):
		var payer: Player = listener if listener else user
		return payer != null and quest_log.can_hand_in(quest, payer.hold)
	return not get_story().is_set(listed.id)


## Whether they have something nobody has heard yet for `listener` (the greeting or an open
## topic; the player talking to them when null); not during their tour (going on with it or ending
## it is no news).
func has_news(listener: Player = null) -> bool:
	if not profile or not profile.dialogue or not presence.talks_here():
		return false
	if routine and routine.tour:
		return false
	var greeting: Topic = get_greeting()
	if greeting and is_new(greeting):
		return true
	return get_choices(listener).any(func(listed: Topic) -> bool: return is_new(listed, listener))


## The greeting their first talk starts with: their tour's offer while they wait at its start,
## else their dialogue's; none at their place before joining or during their tour (it only goes on
## or ends: the greeting waits for afterwards).
func get_greeting() -> Topic:
	if waits_to_join or (routine and routine.tour):
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


## Lets players talk to them while they're here (at their place before joining, while they have
## something to say there), nobody talks to them yet and no overheard talk of theirs plays.
func _update_use() -> void:
	if use_point and presence:
		var here: bool = presence.is_here() and presence.talks_here()
		use_point.enabled = here and not user and not overheard


## Lets them move while they're here (see `NpcPresence`), else stills them, and be talked to.
func _on_presence_changed() -> void:
	_apply_process_mode()
	_update_use()


## Still while they aren't here; while a talk of theirs stopped the game, they keep going.
func _apply_process_mode() -> void:
	if not presence.is_here():
		process_mode = PROCESS_MODE_DISABLED
	else:
		process_mode = PROCESS_MODE_ALWAYS if _pausing else PROCESS_MODE_INHERIT


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


## Stops the game (`GamePause`) or lets it go on; while stopped, they and their talk keep going.
func _set_pausing(paused: bool) -> void:
	if _pausing == paused or not is_inside_tree():
		return
	_pausing = paused
	if paused:
		GamePause.hold(self)
	else:
		GamePause.release(self)
	_apply_process_mode()


## Whether they stand out in a generated location (not aboard or at a station).
func _is_out_there() -> bool:
	var at: Node = get_parent()
	while at:
		if at is GeneratedLocation:
			return true
		at = at.get_parent()
	return false
