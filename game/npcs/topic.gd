class_name Topic
extends Resource
## Something to talk about with an NPC (see `Dialogue`): its title on the talk card and what the
## NPC says about it, one speech bubble per line. It shows once the story flags it `requires` are
## set (and to players who own its `requires_weapon`); hearing it to the end sets its `id` as a
## flag.

## Saved as a story flag once heard (e.g. "quartermaster.ammo"), so it never changes.
@export var id: StringName
## Its button on the talk card (the English text, translated).
@export var title: String
## What the NPC says, one speech bubble each (the English texts, translated).
@export var lines: Array[String] = []
## Story flags it needs before it shows (e.g. another topic's id).
@export var requires: Array[StringName] = []
## A weapon it's about: it only shows to a player who owns it (e.g. Brask once built).
@export var requires_weapon: WeaponType
