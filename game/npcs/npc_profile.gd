class_name NpcProfile
extends Resource
## Who an NPC is (see `Npc`): their name and role on the name plate, how their suit looks and what
## they talk about. An ambient colonist's (see `Colonist`) has a role but no name, and says short
## `remarks` instead.

## Where the profiles are (also in subfolders).
const PEOPLE: String = "res://game/npcs"

## Every profile's path, by its `id` (read once, from `PEOPLE`; paths, since resources held in a
## static variable leak at exit).
static var _paths: Dictionary[StringName, String] = {}

## Who they are in the story's flags (the start of their topics' ids, see `Story`) and later in
## quests, e.g. `quartermaster`: saved, so it never changes; not a name (names may still change).
@export var id: StringName
## Their name (a name: not translated); none for ambient colonists (the plate shows the role).
@export var display_name: String
## What they do, e.g. "Quartermaster" (the English text, translated).
@export var role: String
## Where they're found: a station's `CelestialBody.id` (e.g. `ostra`); empty: aboard the ship.
@export var station: StringName = &""
## Their own model (e.g. assets/npcs/nell/nell.glb: a person made with MakeHuman, with "Idle" and
## "Walk", see docs/technical/characters.md, People). None: the players' suit, in `suit_tint`. A
## path, loaded when the body is made, so reading a profile (e.g. every name for `Keywords`) stays
## cheap.
@export_file("*.glb", "*.tscn") var model: String = ""
## Clips of their model they play now and then while no player is close, one at a time with a pause
## of standing between them (e.g. the bartender wiping the counter, polishing a glass, shelving a
## bottle; see `NpcAnimator`).
@export var activities: Array[StringName] = []
## What their hands hold while they work: a prop's model per grip, put on the model's "<name>Grip"
## marker (its bone shows and hides it, by the clips), e.g. "Glass": assets/props/bar/glass.glb.
@export var props: Dictionary[StringName, PackedScene] = {}
## Their own color: the suit's collar light (the player's shows health instead), their name in a
## radio call.
@export var accent_color: Color = Color(0.3, 0.85, 1.0)
## Multiplies the suit's colors, so NPCs in it look darker than players (not on an own model).
@export var suit_tint: Color = Color(0.7, 0.7, 0.75)
## A crew member's cabin aboard (1–8, see docs/design/ship.md; not used yet). Station NPCs
## have none.
@export_range(1, 8) var cabin: int = 1
@export var dialogue: Dialogue
## Short lines said in passing to a player who stops close by, one after another (the English
## texts, translated).
@export var remarks: Array[String] = []
## What a crew member says over the radio about things that happen (see `CrewReactions`).
@export var reactions: Array[CrewReaction] = []
## A walk through the ship they give (Brannik's), or none.
@export var tour: Tour
## What someone living on a station says when they call the ship because something waits for the
## players there (see `MessageLog`), one of them at random (the English texts, translated).
@export var calls: Array[String] = []
## How many of their requests (quests of kind `Quest.Kind.REQUEST`) are open at a time, offered
## or accepted (see `QuestLog.offered_by`); the depot master has two.
@export_range(0, 4) var open_requests: int = 1


## The lines they have for `event` about `subject`, worded for several players `together` or one
## alone: the subject's own before the ones for any, and within those the ones worded for the
## players before the ones for either; empty: they don't react to it.
func reaction_lines(
	event: StringName, subject: StringName = &"", together: bool = false
) -> Array[String]:
	var fitting: CrewReaction = null
	var best: int = -1
	var wording: CrewReaction.Players = (
		CrewReaction.Players.COOP if together else CrewReaction.Players.SOLO
	)
	for reaction: CrewReaction in reactions:
		if reaction.event != event:
			continue
		if not reaction.subject.is_empty() and reaction.subject != subject:
			continue
		if reaction.players != CrewReaction.Players.ANY and reaction.players != wording:
			continue
		var score: int = (
			(2 if not reaction.subject.is_empty() else 0)
			+ (1 if reaction.players != CrewReaction.Players.ANY else 0)
		)
		if score > best:
			best = score
			fitting = reaction
	return fitting.lines if fitting else ([] as Array[String])


## Every line said in this profile, by who says it (see `VoiceLines.SPEAKING`): theirs, under
## their `id`: the prompts (with a dialogue, `DEFAULT_PROMPT` without any of their own), the
## greeting's and every topic's (also a guest's and the ones for elsewhere), their tour's, their
## reactions' and their remarks, the English texts, each once.
func spoken_lines() -> Dictionary[StringName, PackedStringArray]:
	var said: Array[String] = []
	var topics: Array[Topic] = []
	if dialogue:
		said.append_array(dialogue.get_prompts())
		topics.append(dialogue.greeting)
		topics.append_array(dialogue.topics)
	if tour:
		topics.append_array([tour.offer, tour.invite, tour.resume, tour.abort])
	for topic: Topic in topics:
		if topic:
			said.append_array(topic.lines)
			said.append_array(topic.guest_lines)
			said.append_array(topic.away_lines)
	if tour:
		for stop: TourStop in tour.stops:
			said.append_array(stop.lines)
	for reaction: CrewReaction in reactions:
		said.append_array(reaction.lines)
	said.append_array(remarks)
	said.append_array(calls)
	var once: PackedStringArray = []
	for line: String in said:
		if line not in once:
			once.append(line)
	var by_speaker: Dictionary[StringName, PackedStringArray] = {id: once}
	return by_speaker


## Every profile in `PEOPLE` and its subfolders, named or not (ambient colonists have no name).
static func all() -> Array[NpcProfile]:
	return _profiles_in(PEOPLE)


## The profile whose `id` is `npc` (e.g. a quest's giver), or null.
static func find(npc: StringName) -> NpcProfile:
	if _paths.is_empty():
		for profile: NpcProfile in all():
			_paths[profile.id] = profile.resource_path
	return load(_paths[npc]) as NpcProfile if _paths.has(npc) else null


static func _profiles_in(directory: String) -> Array[NpcProfile]:
	var found: Array[NpcProfile] = []
	for entry: String in ResourceLoader.list_directory(directory):
		var path: String = directory.path_join(entry)
		if entry.ends_with("/"):
			found.append_array(_profiles_in(path.trim_suffix("/")))
		elif entry.ends_with(".tres"):
			var profile := load(path) as NpcProfile
			if profile:
				found.append(profile)
	return found
