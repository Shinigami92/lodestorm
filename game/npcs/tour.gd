class_name Tour
extends Resource
## A walk through the ship a crew member gives (see GAME_DESIGN.md, Spaceship: NPCs; Brannik's,
## `NpcTour` runs it): on a new game they wait at `start` (a marker under the ship's `Tour`) and
## their first talk there is the `offer` (instead of their greeting); `invite` ("Show me the ship")
## opens with it and stays among their topics, so it can be asked for any time. Heard to the end,
## the tour starts: they walk ahead from stop to stop (`stops`, in order) and say each stop's lines
## once the player is close. Talked to during the tour, they offer `resume` and `abort` only.

## The marker (under the ship's `Tour`) where they wait for the first talk on a new game.
@export var start: StringName
## Their first talk while they wait at `start` (heard: they don't wait any more).
@export var offer: Topic
## "Show me the ship": starts the tour once heard to the end.
@export var invite: Topic
## Talked to during the tour: going on ("Go on") or ending it ("End the tour").
@export var resume: Topic
@export var abort: Topic
@export var stops: Array[TourStop] = []
