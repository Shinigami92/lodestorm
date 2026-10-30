class_name Topic
extends Resource
## Something to talk about with an NPC (see `Dialogue`): its title on the talk card and what the
## NPC says about it, one speech bubble per line. It shows once the story flags it `requires` are
## set, to players who own its `requires_weapon`, and once the ship reaches its `requires_body`;
## hearing it to the end sets its `id` as a flag. With `guest_lines`, a guest aboard (a co-op player
## who isn't the host) hears those instead (e.g. the heat shield is the host's to decide on). With
## `away_lines`, the NPC says those while they stand outside their own room (`NpcRoutine.is_away`):
## a topic whose `lines` need the room ("here", "next door", something they point at) says the
## same elsewhere without it.

## Saved as a story flag once heard: the NPC's `NpcProfile.id`, a dot and the topic
## ("quartermaster.ammo", see `Story`), so it never changes.
@export var id: StringName
## Its button on the talk card (the English text, translated).
@export var title: String
## What the NPC says, one speech bubble each (the English texts, translated).
@export var lines: Array[String] = []
## What the NPC says to a guest aboard instead of `lines` (the English texts, translated); none:
## the same `lines` for everyone.
@export var guest_lines: Array[String] = []
## What the NPC says instead of `lines` outside their own room (the English texts, translated;
## a line that fits anywhere repeats the one of `lines`); none: `lines` fit anywhere. A guest's
## `guest_lines` come first, so they must fit anywhere.
@export var away_lines: Array[String] = []
## Story flags it needs before it shows (e.g. another topic's id).
@export var requires: Array[StringName] = []
## A weapon it's about: it only shows to a player who owns it (e.g. Brask once built).
@export var requires_weapon: WeaponType
## A planet or moon it's about (its `CelestialBody.id`): it only shows once the ship reaches it
## (e.g. the bartender's rumors about its regions), so nobody talks about a place out of reach.
@export var requires_body: StringName = &""


## Whether it shows to `listener` (null: nobody in particular) now: `story` has the flags it
## `requires`, `listener` owns its `requires_weapon`, and its `requires_body` is among the bodies
## the ship `reaches` (their ids). Topics with more conditions (a quest's) override it.
func is_open(listener: Player, story: Story, reaches: Array[StringName] = []) -> bool:
	if not story.is_set_all(requires):
		return false
	if not requires_body.is_empty() and requires_body not in reaches:
		return false
	return not requires_weapon or (listener != null and listener.arsenal.owns(requires_weapon))


## The lines a `guest` aboard hears (`guest_lines` when it has them), else the host's: `lines`,
## or `away_lines` (when it has them) while the NPC is `away` from their own room.
func lines_for(guest: bool, away: bool = false) -> Array[String]:
	if guest and not guest_lines.is_empty():
		return guest_lines
	return away_lines if away and not away_lines.is_empty() else lines
