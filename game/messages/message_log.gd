class_name MessageLog
extends Resource
## The ship's messages (see docs/design/story.md, Between missions), listed on the quest board's
## Messages tab: on every return (`come_in`) the catalog's messages whose flags are set come in,
## and everyone waiting at a station (`StationWait`) calls once, unless the ship is docked there.
## They stay to be heard again; heard to the end (`hear`), a catalog message sets its flag for the
## ship. It's the host's (the ship's), saved with the ship.

const CATALOG: MessageCatalog = preload("res://game/messages/messages.tres")

## Every message there is.
var catalog: MessageCatalog = CATALOG
## The story the messages wait for and their flags go into (the ship's).
var story := Story.new()
## The ship's story director (its waiting beats, its quests' steps).
var director := StoryDirector.new()
## What came in, oldest first.
var received: Array[ReceivedMessage] = []
## What called the ship already (a `StationWait.key` each), so it calls only once.
var called: Array[StringName] = []
## Picks the call lines.
var rng := RandomNumberGenerator.new()


## How many messages weren't heard yet.
func unheard() -> int:
	return received.filter(func(entry: ReceivedMessage) -> bool: return not entry.heard).size()


## Who waits at the station `station` (its id) now; empty: at any station.
func waits(station: StringName = &"") -> Array[StationWait]:
	var found: Array[StationWait] = StationWait.find_all(director)
	if not station.is_empty():
		found.assign(found.filter(func(wait: StationWait) -> bool: return wait.station == station))
	return found


## A return with the ship at the body `body` (its id): the catalog's messages whose flags are set
## come in, and everyone newly waiting at a station calls (once; not at the station the ship is
## docked at, and not while an earlier call of theirs is still unheard). Returns what came in.
func come_in(body: StringName) -> Array[ReceivedMessage]:
	var came: Array[ReceivedMessage] = []
	var calls_before: int = called.size()
	for message: Message in catalog.messages:
		if not _has(message) and story.is_set_all(message.requires):
			came.append(ReceivedMessage.new(message))
	for wait: StationWait in waits():
		if wait.key in called:
			continue
		called.append(wait.key)
		var profile: NpcProfile = NpcProfile.find(wait.npc)
		if wait.station == body or not profile or profile.calls.is_empty():
			continue
		if (received + came).any(
			func(entry: ReceivedMessage) -> bool:
				return entry.is_call() and not entry.heard and entry.message.from == wait.npc
		):
			continue
		came.append(ReceivedMessage.calling(profile, _call_line(profile)))
	received.append_array(came)
	if not came.is_empty() or called.size() != calls_before:
		emit_changed()
	return came


## Notes `entry` heard to the end (a catalog message's flag set).
func hear(entry: ReceivedMessage) -> void:
	if entry.heard:
		return
	entry.heard = true
	if not entry.is_call():
		story.set_flag(entry.message.flag())
	emit_changed()


## What's saved: what came in (a catalog message's id, or a call's sender and line; heard or not)
## and what called.
func save_data() -> Dictionary:
	var saved: Array = []
	for entry: ReceivedMessage in received:
		var data: Dictionary = {"heard": entry.heard}
		if entry.is_call():
			data["from"] = String(entry.message.from)
			data["call"] = entry.call_line
		else:
			data["id"] = String(entry.message.id)
		saved.append(data)
	return {
		"received": saved,
		"called": called.map(func(key: StringName) -> String: return String(key)),
	}


## Reads what a save has (`save_data`), without messages no longer in the `catalog` and calls whose
## line is gone. Returns whether all of it read.
func load_data(saved: Variant) -> bool:
	if saved == null:
		return true
	if not saved is Dictionary:
		return SaveData.skipped("messages", saved)
	var data: Dictionary = saved
	var complete: bool = true
	received.clear()
	var saved_received: Variant = data.get("received", [])
	for item: Variant in saved_received if saved_received is Array else []:
		var entry: ReceivedMessage = _read_entry(item)
		if entry:
			received.append(entry)
		else:
			complete = SaveData.skipped("message", item)
	called.clear()
	var saved_called: Variant = data.get("called", [])
	for key: Variant in saved_called if saved_called is Array else []:
		if key is String and Story.is_valid_flag(StringName(key as String)):
			called.append(StringName(key as String))
		else:
			complete = SaveData.skipped("call", key)
	emit_changed()
	return complete and saved_received is Array and saved_called is Array


## Whether `message` came in already.
func _has(message: Message) -> bool:
	return received.any(func(entry: ReceivedMessage) -> bool: return entry.message == message)


## A line of `profile`'s calls at random, never the one of their last call (with more than one).
func _call_line(profile: NpcProfile) -> int:
	var last: int = -1
	for entry: ReceivedMessage in received:
		if entry.is_call() and entry.message.from == profile.id:
			last = entry.call_line
	var count: int = profile.calls.size()
	if count < 2 or last < 0 or last >= count:
		return rng.randi_range(0, count - 1)
	return (last + rng.randi_range(1, count - 1)) % count


## A saved entry (`save_data`) read, or null when it doesn't read.
func _read_entry(item: Variant) -> ReceivedMessage:
	if not item is Dictionary:
		return null
	var data: Dictionary = item
	var entry: ReceivedMessage = null
	var id: Variant = data.get("id")
	var from: Variant = data.get("from")
	if id is String:
		var message: Message = catalog.find(StringName(id as String))
		entry = ReceivedMessage.new(message) if message else null
	elif from is String:
		var profile: NpcProfile = NpcProfile.find(StringName(from as String))
		var line: int = int(SaveData.number(data.get("call"), -1.0))
		if profile and line >= 0 and line < profile.calls.size():
			entry = ReceivedMessage.calling(profile, line)
	if entry:
		entry.heard = data.get("heard") == true
	return entry
