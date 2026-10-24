class_name Topic
extends Resource
## Something to talk about with an NPC (see `Dialogue`): its title on the talk card and what the
## NPC says about it, one speech bubble per line. It shows once the story flags it `requires` are
## set, to players who own its `requires_weapon`, and once the ship reaches its `requires_body`;
## hearing it to the end sets its `id` as a flag.

## Saved as a story flag once heard: the NPC's `NpcProfile.id`, a dot and the topic
## ("quartermaster.ammo", see `Story`), so it never changes.
@export var id: StringName
## Its button on the talk card (the English text, translated).
@export var title: String
## What the NPC says, one speech bubble each (the English texts, translated).
@export var lines: Array[String] = []
## Story flags it needs before it shows (e.g. another topic's id).
@export var requires: Array[StringName] = []
## A weapon it's about: it only shows to a player who owns it (e.g. Brask once built).
@export var requires_weapon: WeaponType
## A planet or moon it's about (its `CelestialBody.id`): it only shows once the ship reaches it
## (e.g. the bartender's rumors about its regions), so nobody talks about a place out of reach.
@export var requires_body: StringName = &""


## Whether it shows to `listener` (null: nobody in particular) now: `story` has the flags it
## `requires`, `listener` owns its `requires_weapon`, and its `requires_body` is among the bodies
## the ship `reaches` (their ids). Topics with more conditions (a quest's, reputation) override it.
func is_open(listener: Player, story: Story, reaches: Array[StringName] = []) -> bool:
	if not story.is_set_all(requires):
		return false
	if not requires_body.is_empty() and requires_body not in reaches:
		return false
	return not requires_weapon or (listener != null and listener.arsenal.owns(requires_weapon))
