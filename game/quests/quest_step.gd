class_name QuestStep
extends Resource
## One step of a `Quest`: its `goals`, then a hand-in at an NPC (the giver, or the one it names),
## who pays its rewards and says its `hand_in` lines. Handed in, its flag is set
## (`Quest.step_flag`) and the next step starts.

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
## Reputation with the quest's giver it pays (pips, up to `QuestLog.REPUTATION_MAX`).
@export_range(0, 5) var reputation: int = 0
