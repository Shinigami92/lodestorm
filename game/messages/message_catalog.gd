class_name MessageCatalog
extends Resource
## Every message in the game (`game/messages/messages.tres`), in the order they come in when
## several do on one return.

@export var messages: Array[Message] = []


## The message with `id`, or null.
func find(id: StringName) -> Message:
	for message: Message in messages:
		if message.id == id:
			return message
	return null
