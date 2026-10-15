class_name NpcProfile
extends Resource
## Who an NPC is (see `Npc`): their name and role on the name plate, how their suit looks and what
## they talk about.

## Their name (a name: not translated).
@export var display_name: String
## What they do aboard, e.g. "Quartermaster" (the English text, translated).
@export var role: String
## Their own color: the suit's collar light (the player's shows health instead).
@export var accent_color: Color = Color(0.3, 0.85, 1.0)
## Multiplies the suit's colors, so crew look darker than players.
@export var suit_tint: Color = Color(0.7, 0.7, 0.75)
## Their crew cabin aboard (1–8, see GAME_DESIGN.md, Spaceship); not used yet.
@export_range(1, 8) var cabin: int = 1
@export var dialogue: Dialogue
