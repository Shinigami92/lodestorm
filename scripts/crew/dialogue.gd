class_name Dialogue
extends Resource
## What an NPC talks about: the `greeting` plays by itself the first time a player talks to them,
## then the talk card lists the `topics` that are open (see `Topic`), while the NPC's speech
## bubble shows the `prompt`. Topics can be heard again any time, so what the crew explains can
## always be looked up again. Later, quests add their own topics.

## Played by itself the first time anyone talks to the NPC (heard: its id is set); none: straight
## to the topics.
@export var greeting: Topic
## What the NPC says while the player picks a topic (the English text, translated).
@export var prompt: String = "What do you need?"
@export var topics: Array[Topic] = []
