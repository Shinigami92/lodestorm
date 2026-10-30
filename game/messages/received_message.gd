class_name ReceivedMessage
extends RefCounted
## A message on the ship's list (`MessageLog`): one from the catalog, or a call from someone waiting
## at a station (`call_line`, the line of their `NpcProfile.calls`), and whether it was heard.

## What it says and who from (made for a call).
var message: Message
## For a call: which of its sender's `NpcProfile.calls` it is; -1: from the catalog.
var call_line: int = -1
## Whether it was heard to the end.
var heard: bool = false


func _init(of_message: Message, line: int = -1) -> void:
	message = of_message
	call_line = line


## A call from `profile` with their call line `line`.
static func calling(profile: NpcProfile, line: int) -> ReceivedMessage:
	var said := Message.new()
	said.from = profile.id
	said.lines.append(profile.calls[line])
	return ReceivedMessage.new(said, line)


## Whether it's a call (not from the catalog).
func is_call() -> bool:
	return call_line >= 0
