class_name SkillRank
extends Resource
## One rank of a `Skill`: what it costs and what the skill does at that rank. Values TBD
## (playtest).

## Ore taken from the player's hold for this rank, in units per ore type.
@export var cost: Dictionary[OreType, int] = {}
## What the skill does at this rank, all ranks so far together (e.g. 40: +40 health at rank 2);
## its meaning is up to the skill's `effect`.
@export var value: float = 1.0
