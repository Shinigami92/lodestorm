class_name Quest
extends Resource
## A job an NPC gives the players (see docs/design/missions.md, Quests): their `giver` offers it
## once it's open (`is_open`, a diamond marker above them), its `offer` tells what it's about, and
## the card after it accepts it or leaves it for later. Then its `steps` are done one after another,
## each handed in at an NPC. What's done is the ship's (`QuestLog`, story flags); what it asks and
## pays is here. A quest never fails: a step stays open until it's handed in.

## What kind of job it is (the quest board groups them).
enum Kind { MAIN, SIDE, REQUEST }

## Who it is in the story's flags (`flag`, `step_flag`) and the save, e.g. `ammo_run`: saved, so it
## never changes; not its title (titles may still change).
@export var id: StringName
## Its name on the cards and the quest board (the English text, translated).
@export var title: String
@export var kind: Kind = Kind.SIDE
## Who offers it: their `NpcProfile.id`.
@export var giver: StringName
## Story flags it needs before it's offered (e.g. another quest's `flag`).
@export var requires: Array[StringName] = []
## A story flag that keeps it from being offered once set (e.g. a crew member's
## `NpcProfile.join_flag`: nobody asks the players to find someone already aboard); empty: none.
@export var until: StringName = &""
## A planet or moon it's about (its `CelestialBody.id`): only offered once the ship reaches it.
@export var requires_body: StringName = &""
## What the giver says about it, a topic in their list while it's offered (e.g. "About that
## job..."); heard to the end, the offer card shows what it asks and pays. Its `id` is the giver's
## (`<giver>.<topic>`, see `Story`).
@export var offer: Topic
@export var steps: Array[QuestStep] = []


## Its story flag, set once its last step is handed in: `quest.<id>`.
func flag() -> StringName:
	return StringName("quest.%s" % id)


## The story flag of `step` (one of `steps`), set once it's handed in: `quest.<id>.<step>`.
func step_flag(step: QuestStep) -> StringName:
	return StringName("quest.%s.%s" % [id, step.id])


## Whether its giver offers it now: `story` has the flags it `requires` (and not its `until`),
## its `requires_body` is among the bodies the ship `reaches` (their ids). Whether it's accepted
## already is the `QuestLog`'s.
func is_open(story: Story, reaches: Array[StringName]) -> bool:
	if not story.is_set_all(requires) or (not until.is_empty() and story.is_set(until)):
		return false
	return requires_body.is_empty() or requires_body in reaches


## Who hands `step` in: the NPC it names, else the giver (their `NpcProfile.id`).
func hand_in_npc(step: QuestStep) -> StringName:
	return step.hand_in_to if not step.hand_in_to.is_empty() else giver


## The ores and alloys all its steps pay, summed per item (for the offer card).
func reward_items() -> Dictionary[ItemType, int]:
	var items: Dictionary[ItemType, int] = {}
	for step: QuestStep in steps:
		for item: ItemType in step.items:
			items[item] = items.get(item, 0) + step.items[item]
	return items


## Every line said in it, by who says it (see `VoiceLines.SPEAKING`): the offer's by the giver,
## each step's hand-in, prompts at their place and radio calls (alone and together) by the NPC
## it's handed in at (a call by its `RadioLine.speaker` if it names one), the English texts, each
## once.
func spoken_lines() -> Dictionary[StringName, PackedStringArray]:
	var by_speaker: Dictionary[StringName, PackedStringArray] = {}
	_add_lines(by_speaker, giver, offer)
	for step: QuestStep in steps:
		var npc: StringName = hand_in_npc(step)
		_add_lines(by_speaker, npc, step.hand_in)
		var prompts := Topic.new()
		prompts.lines.assign(step.place_prompts)
		_add_lines(by_speaker, npc, prompts)
		for said: RadioLine in step.radio_lines():
			var radio := Topic.new()
			radio.lines.append(said.text)
			if not said.coop_text.is_empty():
				radio.lines.append(said.coop_text)
			_add_lines(by_speaker, said.speaker if not said.speaker.is_empty() else npc, radio)
	return by_speaker


static func _add_lines(
	by_speaker: Dictionary[StringName, PackedStringArray], speaker: StringName, topic: Topic
) -> void:
	if not topic:
		return
	var lines: PackedStringArray = by_speaker.get(speaker, PackedStringArray())
	for line: String in topic.lines + topic.guest_lines + topic.away_lines:
		if line not in lines:
			lines.append(line)
	by_speaker[speaker] = lines
