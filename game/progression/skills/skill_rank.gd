class_name SkillRank
extends Resource
## One rank of a `Skill`: what it costs, how long it takes and what the skill does at that rank.
## Values TBD (playtest).

## What's taken from the player's hold for this rank, in units per item (ores so far).
@export var cost: Dictionary[ItemType, int] = {}
## How long learning it takes on the wall clock once paid, in seconds (see `Skills.start`).
@export var seconds: float = 0.0
## What the skill does at this rank, all ranks so far together (e.g. 40: +40 health at rank 2);
## its meaning is up to the skill's `effect`.
@export var value: float = 1.0
