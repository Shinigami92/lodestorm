class_name OverheardTalks
extends Node
## The ship's overheard talks as they happen (`Ship.talks`, see `OverheardTalk`): the first talk of
## the catalog that's open (its flags set, played not yet) and can be held now (its spot and both
## speakers there: aboard, or at the station the ship is docked at) waits; its speakers walk to the
## spot's places (`NpcRoutine.talk_place`) and wait there. Once both stand there, nobody talks to
## them and a player is within `START_RANGE` m of the spot, it starts: one line after another in
## the speaker's bubble and voice (`Npc.say_aside`), each as long as a line moving on by itself,
## to the end whether anyone stays or not, while neither can be talked to (`Npc.overheard`). At its
## end its flag is set and they go back to what they did. Nothing of it is saved but the flag: a
## talk cut off by loading waits again.

## How close a player must come to the spot for a waiting talk to start, in m. TBD (playtest).
const START_RANGE: float = 6.0
## Seconds between looking for the talk to wait for.
const PICK_TIME: float = 0.5

const CATALOG: TalkCatalog = preload("res://game/talks/talks.tres")

## Every talk there is.
var catalog: TalkCatalog = CATALOG
## Whose talks they are (their flags go into its story).
var ship: Ship
## The talk waiting or playing, or null.
var talk: OverheardTalk

## Where it's held, and who says its lines (by `NpcProfile.id`).
var _spot: TalkSpot
var _cast: Dictionary[StringName, Npc] = {}
## A talk to hold before the catalog's (the debug overlay's), or null.
var _forced: OverheardTalk
## The line being said (-1: not playing), who says it and the seconds it still shows.
var _line: int = -1
var _speaker: Npc
var _line_left: float = 0.0
var _pick_left: float = 0.0


func _physics_process(delta: float) -> void:
	if is_playing():
		_go_on(delta)
		return
	_pick_left -= delta
	if _pick_left <= 0.0:
		_pick_left = PICK_TIME
		_pick()
	if talk and _can_start():
		_start()


## Whether a talk is being played right now.
func is_playing() -> bool:
	return _line >= 0


## Holds `held` (a talk outside the catalog, e.g. the debug overlay's) before any other once its
## spot and speakers are there; its flag isn't set at its end.
func hold(held: OverheardTalk) -> void:
	_forced = held
	_pick_left = 0.0


## Picks the talk to wait for: the held one, else the catalog's first that's open and can be held
## now; sends its speakers to the spot (and the ones of a talk no longer picked back).
func _pick() -> void:
	var story: Story = ship.story if ship else Story.new()
	var picked: OverheardTalk = null
	var candidates: Array[OverheardTalk] = []
	if _forced:
		candidates.append(_forced)
	candidates.append_array(catalog.talks.filter(_is_open.bind(story)))
	var spot: TalkSpot = null
	var cast: Dictionary[StringName, Npc] = {}
	for candidate: OverheardTalk in candidates:
		spot = TalkSpot.find(get_tree(), candidate.spot)
		cast = _find_cast(candidate)
		if spot and cast.size() == candidate.speakers().size():
			picked = candidate
			break
	if picked == talk and spot == _spot and cast == _cast:
		return
	_release()
	if not picked:
		return
	talk = picked
	_spot = spot
	_cast = cast
	var speakers: Array[StringName] = talk.speakers()
	for index: int in speakers.size():
		_cast[speakers[index]].routine.talk_place = _spot.get_place(index)


func _is_open(candidate: OverheardTalk, story: Story) -> bool:
	return candidate.is_open(story) and candidate.speakers().size() == 2


## Whether `npc` is a crew member there aboard (not at their place before joining).
static func _is_aboard(npc: Npc) -> bool:
	return npc.is_present() and not npc.waits_to_join


## The NPCs who say `candidate`'s lines, by `NpcProfile.id` (the ones found and aboard).
func _find_cast(candidate: OverheardTalk) -> Dictionary[StringName, Npc]:
	var cast: Dictionary[StringName, Npc] = {}
	var speakers: Array[StringName] = candidate.speakers()
	for menu: Node in get_tree().get_nodes_in_group(WorldMenu.GROUP):
		var npc := menu as Npc
		if npc and npc.profile and npc.profile.id in speakers and _is_aboard(npc):
			cast[npc.profile.id] = npc
	return cast


## Whether the waiting talk can start: both at their places, nobody talking to them, a player
## close.
func _can_start() -> bool:
	if not is_instance_valid(_spot) or not _cast_valid():
		_release()
		return false
	for npc: Npc in _cast.values():
		if npc.user or not npc.routine.is_at_talk_place():
			return false
	return Player.nearest(get_tree(), _spot.global_position, START_RANGE) != null


func _start() -> void:
	for npc: Npc in _cast.values():
		npc.overheard = true
	_line = 0
	_say()


## Counts the line's time down, then says the next one or ends the talk; ends it at once when one
## of them is gone (a station left behind).
func _go_on(delta: float) -> void:
	if not _cast_valid():
		_finish()
		return
	_line_left -= delta
	if _line_left > 0.0:
		return
	_line += 1
	if _line < talk.lines.size():
		_say()
	else:
		_finish()


func _say() -> void:
	var line: TalkLine = talk.lines[_line]
	var speaker: Npc = _cast[line.npc]
	if _speaker and _speaker != speaker and is_instance_valid(_speaker):
		_speaker.say_aside("")
	_speaker = speaker
	_line_left = speaker.say_aside(line.text)


## Ends the talk played: the last bubble out, its flag set (a catalog talk's), its speakers back.
func _finish() -> void:
	if is_instance_valid(_speaker):
		_speaker.say_aside("")
	if ship and talk in catalog.talks:
		ship.story.set_flag(talk.flag())
	if talk == _forced:
		_forced = null
	_release()


## Lets the speakers of the talk waiting or played go back to what they did.
func _release() -> void:
	for npc: Npc in _cast.values():
		if is_instance_valid(npc):
			npc.overheard = false
			npc.routine.talk_place = null
	_cast = {}
	_spot = null
	_speaker = null
	talk = null
	_line = -1


func _cast_valid() -> bool:
	return _cast.values().all(func(npc: Npc) -> bool: return is_instance_valid(npc))
