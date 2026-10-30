@abstract class_name QuestGoal
extends Resource
## Something a `QuestStep` asks for. Each kind is a Resource of its own (a delivery, a run's
## mining, something built aboard), so a new kind is code once and data after. Its progress is the
## ship's (`QuestLog`), a number up to `target`; the goal only says how it grows.

## What it says on the cards and the quest board (translated), e.g. "Deliver Kyrite".
@abstract func describe() -> String


## How much it needs (1: done or not).
func target() -> float:
	return 1.0


## How much of `target` the cards count as a number (more than 1: "3 / 5"); `target` by default (a
## hunt counts only its kills, not its brood nest).
func counted() -> float:
	return target()


## What it takes of a `haul` brought aboard (units per ore) towards it, with `progress` so far
## (units per ore; its progress grows by their sum); nothing by default.
func take_from(_haul: Dictionary[OreType, float], _progress: float) -> Dictionary[OreType, float]:
	return {}


## Its progress after a haul brought aboard, with `run` everything brought aboard this run so far
## (units per ore); `progress` unchanged by default.
func count_run(_run: Dictionary[OreType, float], progress: float) -> float:
	return progress


## Whether one of `players` has it done (something built); false by default.
func is_built(_players: Array[Player]) -> bool:
	return false


## What can still be paid towards it from the hold at the hand-in, with `progress` so far (units
## per item); nothing by default.
func missing(_progress: float) -> Dictionary[ItemType, int]:
	return {}
