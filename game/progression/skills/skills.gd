class_name Skills
extends Resource
## The skill ranks a player learned at the skill graph; everything else is rank 0. Each player has
## their own (like their `Upgrades`).

## Rank per learned skill.
@export var ranks: Dictionary[Skill, int] = {}


## The rank of `skill` (0 when it's not learned or null).
func rank(skill: Skill) -> int:
	if not skill:
		return 0
	var learned: int = ranks.get(skill, 0)
	return learned


## Whether `skill` can be learned: what it requires is learned.
func is_open(skill: Skill) -> bool:
	return skill != null and (not skill.requires or rank(skill.requires) >= 1)


## The rank to learn next for `skill`, or null when it's at its highest.
func next_rank(skill: Skill) -> SkillRank:
	return skill.rank_after(rank(skill)) if skill else null


## Raises `skill` by one rank if it's open and not at its highest. Returns whether it rose.
## Paying for it is up to the caller (see `PlayerHold.pay`).
func raise(skill: Skill) -> bool:
	if not is_open(skill) or not next_rank(skill):
		return false
	ranks[skill] = rank(skill) + 1
	emit_changed()
	return true


## What the learned skills with `effect` do together (0 when none is learned).
func value(effect: Skill.Effect) -> float:
	var total: float = 0.0
	for skill: Skill in ranks:
		if skill.effect == effect:
			total += skill.value_at(ranks[skill])
	return total


## Whether a skill with `effect` is learned.
func has(effect: Skill.Effect) -> bool:
	for skill: Skill in ranks:
		if skill.effect == effect and ranks[skill] >= 1:
			return true
	return false
