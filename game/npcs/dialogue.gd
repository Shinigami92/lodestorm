class_name Dialogue
extends Resource
## What an NPC talks about: the `greeting` plays by itself the first time a player talks to them,
## then the talk card lists the `topics` that are open (see `Topic`), while the NPC's speech
## bubble shows one of the `prompts`. Topics can be heard again any time, so what the crew explains
## can always be looked up again. Later, quests add their own topics.

## What an NPC says while the player picks a topic when they have no `prompts` of their own.
const DEFAULT_PROMPT: String = "How can I help you?"

## Played by itself the first time anyone talks to the NPC (heard: its id is set); none: straight
## to the topics.
@export var greeting: Topic
## What the NPC says while the player picks a topic, one picked at random for each talk, never
## the one of the talk before (the English texts, translated); none: `DEFAULT_PROMPT`.
@export var prompts: Array[String] = []
## What a crew member says instead at their place before joining (`Npc.waits_to_join`, e.g. Hollis
## at his camp, where the crew's "the miners won't fix themselves" doesn't fit; the English texts,
## translated); none: `prompts`.
@export var place_prompts: Array[String] = []
@export var topics: Array[Topic] = []


## The prompts to pick from: `prompts` (at their place before joining, `place_prompts` if there
## are any), or `DEFAULT_PROMPT` without any.
func get_prompts(at_place: bool = false) -> Array[String]:
	if at_place and not place_prompts.is_empty():
		return place_prompts
	return prompts if not prompts.is_empty() else ([DEFAULT_PROMPT] as Array[String])


## A prompt for the next talk (`at_place`: at their place before joining): any of `get_prompts`,
## but not `last` (the one before) when there's another.
func pick_prompt(last: String = "", at_place: bool = false) -> String:
	var choices: Array[String] = get_prompts(at_place).filter(
		func(prompt: String) -> bool: return prompt != last
	)
	if choices.is_empty():
		return get_prompts(at_place)[0]
	var picked: String = choices.pick_random()
	return picked
