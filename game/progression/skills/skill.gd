class_name Skill
extends Resource
## Something a player learns at the skill graph (see GAME_DESIGN.md, Progression): dash, more
## health, ... Bought rank by rank with ore from the player's hold; most skills have a single rank.
## A skill opens once the one it `requires` is learned. What it does is its `effect`, read by its
## user (e.g. `Player.max_health` adds the `HEALTH` value). The ranks a player learned are in their
## `Skills`.

## What a skill does; skills with the same effect add up.
enum Effect {
	NONE,
	## More health (`value`: extra HP, before the armor's multiplier).
	HEALTH,
	## Health comes back after a while without damage (`value`: HP per s).
	REGENERATION,
	## A short burst in the move direction (`value` unused).
	DASH,
	## Reloading at full walking speed.
	RELOAD_ON_THE_MOVE,
	## More spare magazines per ranged weapon (`value`: how many more).
	SPARE_MAGAZINES,
	## A magazine reload keeps the rounds left in it.
	CAREFUL_RELOAD,
	## An arrow to the nearest free ore node (`value`: its range in m).
	ORE_SCANNER,
	## Numbers on hit aliens.
	DAMAGE_READOUT,
}

## Player-facing name.
@export var display_name: String = ""
## One line on what it does, shown on the card.
@export var description: String = ""
@export var effect: Effect = Effect.NONE
## Its ranks, in order (at least one).
@export var ranks: Array[SkillRank] = []
## The skill that must be learned first, or null: one of the cluster's roots.
@export var requires: Skill
## Where it sits in its cluster's constellation, from the cluster's center, in m (x right, y up).
@export var graph_position: Vector2 = Vector2.ZERO


## How deep in its cluster's tree it sits: 1 for a root, one more per skill before it. Deeper skills
## cost rarer ores: commons at depth 1, a mid ore from depth 2, a signature ore from depth 4 (see
## GAME_DESIGN.md, Progression).
func depth() -> int:
	return requires.depth() + 1 if requires else 1


## The highest rank.
func max_rank() -> int:
	return ranks.size()


## The rank that comes after `rank` (0: not learned), or null at the highest.
func rank_after(rank: int) -> SkillRank:
	return ranks[rank] if rank >= 0 and rank < ranks.size() else null


## What it does at `rank` (0 at rank 0).
func value_at(rank: int) -> float:
	return ranks[mini(rank, ranks.size()) - 1].value if rank >= 1 and not ranks.is_empty() else 0.0
