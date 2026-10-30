class_name BoardEntry
extends RefCounted
## A line on the quest board's list (see `QuestBoardStation`, `BoardLists`): a group's heading, a
## note (nothing to list), a quest, the done quests' group (opened and closed from its card), a
## job or a message. Its texts are translated already.

enum Kind { HEADING, NOTE, QUEST, DONE, JOB, MESSAGE }

var kind: Kind = Kind.NOTE
## Its text on the list (a job's with its level, e.g. "Harl · Damage MK3").
var title: String = ""
## What it says on the right: a quest's giver, a job's time left, "Done" or who left a message.
var note: String = ""
## How far it is (0–1, a quest's active step), shown as a bar; below 0: none.
var progress: float = -1.0
## Its quest (`Kind.QUEST`).
var quest: Quest
## Whether its quest is done.
var done: bool = false
## Whether its quest is the tracked one.
var tracked: bool = false
## Its message (`Kind.MESSAGE`).
var received: ReceivedMessage
## A job's status, e.g. "MK3 under way" or "MK3 done".
var status: String = ""
## When a job under way is done (Unix seconds); 0: finished.
var ends_at: float = 0.0
## What keeps it apart from the other lines when the list is made again (the selection stays on
## it).
var key: String = ""


func _init(of_kind: Kind = Kind.NOTE, text: String = "", id: String = "") -> void:
	kind = of_kind
	title = text
	key = id if not id.is_empty() else "%d:%s" % [of_kind, text]


## Whether the highlight can rest on it (not a heading or a note).
func is_selectable() -> bool:
	return kind != Kind.HEADING and kind != Kind.NOTE
