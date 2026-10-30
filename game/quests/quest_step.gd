class_name QuestStep
extends Resource
## One step of a `Quest`: its `goals`, then a hand-in at an NPC (the giver, or the one it names),
## who pays its rewards and says its `hand_in` lines. Handed in, its flag is set
## (`Quest.step_flag`) and the next step starts.

## The radio calls' keys (`radio_line`, saved with the ship once heard): its `ready_line`.
const READY: StringName = &"ready"

## Who it is in the story's flags (`quest.<quest>.<step>`): saved, so it never changes.
@export var id: StringName
## What it asks, on the cards and the quest board (the English text, translated), e.g. "Bring
## Brannik 300 Kyrite for the range."
@export var text: String
## What has to be done before it's handed in (all of them).
@export var goals: Array[QuestGoal] = []
## Who it's handed in at: their `NpcProfile.id`; empty: the quest's giver.
@export var hand_in_to: StringName = &""
## Its entry in that NPC's list while it's active (its title), and what they say once it's handed
## in (its lines, e.g. thanks and what comes next). Its `id` is theirs (`<npc>.<topic>`).
@export var hand_in: Topic
## Ores and alloys it pays at the hand-in, into the hold of every player there.
@export var items: Dictionary[ItemType, int] = {}
## A blueprint it pays: every player there learns it.
@export var blueprint: WeaponType
## Furnaces it unlocks in the ship's refinery (see `Furnaces`), lit at the hand-in.
@export_range(0, 4) var furnaces: int = 0
## Miners' cradles it opens on the ship (see `Cradles`) at the hand-in.
@export_range(0, 4) var cradles: int = 0
## What its NPC says over the radio once all its goals are done, instead of the last one's
## `QuestGoal.done_line` (e.g. "That's the second nest. Come back to me."; see `QuestRadio`), or
## null.
@export var ready_line: RadioLine


## The key of goal `index`'s `RegionGoal.landing_line` (see `radio_line`).
static func landing_key(index: int) -> StringName:
	return StringName("landing.%d" % index)


## The key of goal `index`'s `QuestGoal.done_line` (see `radio_line`).
static func done_key(index: int) -> StringName:
	return StringName("done.%d" % index)


## Its radio call for `key` (`READY`, `landing_key` or `done_key`), or null (none, or a goal it
## doesn't have).
func radio_line(key: StringName) -> RadioLine:
	if key == READY:
		return ready_line
	var parts: PackedStringArray = String(key).split(".")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	var index: int = parts[1].to_int()
	if index < 0 or index >= goals.size():
		return null
	if parts[0] == "done":
		return goals[index].done_line
	var goal := goals[index] as RegionGoal
	return goal.landing_line if parts[0] == "landing" and goal else null


## Every radio line it has (each goal's landing and done lines, then its ready line).
func radio_lines() -> Array[RadioLine]:
	var found: Array[RadioLine] = []
	for goal: QuestGoal in goals:
		var in_region := goal as RegionGoal
		for line: RadioLine in [in_region.landing_line if in_region else null, goal.done_line]:
			if line:
				found.append(line)
	if ready_line:
		found.append(ready_line)
	return found
