class_name RadioLine
extends Resource
## A quest's call over the radio (see `QuestRadio`): what the NPC a step is handed in at says when
## the players land in a goal's region, when a goal is done or when the whole step is (or its
## `speaker`, e.g. the pilot for someone who has no radio yet). Worded for a player alone, and for
## several together when that reads differently (German du/ihr).

## What they say (the English text, translated).
@export var text: String
## What they say to several players together instead (the English text, translated); empty: the
## same `text`.
@export var coop_text: String
## Who says it (their `NpcProfile.id`); empty: the NPC the step is handed in at.
@export var speaker: StringName = &""


## The line for several players `together` or one (English).
func for_players(together: bool) -> String:
	return coop_text if together and not coop_text.is_empty() else text
