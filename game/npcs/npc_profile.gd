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
## Their own color: the suit's collar light (the player's shows health instead).
@export var accent_color: Color = Color(0.3, 0.85, 1.0)
## Multiplies the suit's colors, so crew look darker than players.
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
