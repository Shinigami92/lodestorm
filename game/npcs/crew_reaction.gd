class_name CrewReaction
extends Resource
## What a crew member says over the radio about something that happened (see `CrewReactions`).
## Kept in their `NpcProfile.reactions`.

## Who the lines are worded for: a player alone, several together, or either.
## Saved by number in resources: add new values at the end.
enum Players { ANY, SOLO, COOP }

## What it reacts to: one of `CrewReactions`' events (e.g. `first_run_won`).
@export var event: StringName = &""
## Only for this subject of the event, e.g. a `CelestialBody.id` for a planet opened or a body
## landed on; empty: for any. A subject's own lines go before the ones for any.
@export var subject: StringName = &""
## Whether these lines are for a player alone, for several together, or for either (a
## `SOLO`/`COOP` reaction goes before an `ANY` one when it fits).
@export var players: Players = Players.ANY
## Story flags these lines need (e.g. the join flags of the crew members they name); a reaction
## with them goes before one without when they're set, so it repeats that one's lines and adds the
## ones naming them.
@export var requires: Array[StringName] = []
## What they say, one line each time, in turn (the English texts, translated).
@export var lines: Array[String] = []
