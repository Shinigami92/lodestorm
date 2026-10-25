class_name NpcProfile
extends Resource
## Who an NPC is (see `Npc`): their name and role on the name plate, how their suit looks and what
## they talk about. An ambient colonist's (see `Colonist`) has a role but no name, and says short
## `remarks` instead.

## Who they are in the story's flags (the start of their topics' ids, see `Story`) and later in
## quests and reputation, e.g. `quartermaster`: saved, so it never changes; not a name (names may
## still change).
@export var id: StringName
## Their name (a name: not translated); none for ambient colonists (the plate shows the role).
@export var display_name: String
## What they do, e.g. "Quartermaster" (the English text, translated).
@export var role: String
## Their own model (e.g. assets/npcs/nell/nell.glb: a person made with MakeHuman, with "Idle" and
## "Walk", see docs/TECHNICAL.md, People). None: the players' suit, in `suit_tint`.
@export var model: PackedScene
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
## Multiplies the suit's colors, so crew look darker than players (not on an own model).
@export var suit_tint: Color = Color(0.7, 0.7, 0.75)
## What they wear over the suit, so they read apart from the camera (greybox until their own model,
## e.g. the pilot's headset): a scene whose children are named after the suit model's bones and
## placed in its rest pose (in m, the feet at the origin, facing +z); each follows its bone (see
## `NpcBody`). None: the bare suit.
@export var accessory: PackedScene
## A crew member's cabin aboard (1–8, see GAME_DESIGN.md, Spaceship; not used yet). Station NPCs
## have none.
@export_range(1, 8) var cabin: int = 1
@export var dialogue: Dialogue
## Short lines said in passing to a player who stops close by, one after another (the English
## texts, translated).
@export var remarks: Array[String] = []
## What a crew member says over the radio about things that happen (see `CrewReactions`).
@export var reactions: Array[CrewReaction] = []


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
