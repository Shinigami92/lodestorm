class_name NpcTalk
extends RefCounted
## The talk a player has with a crew member (`npc`, see docs/design/crew.md) while it's open: the
## card beside them (a `TalkCard`) lists their open topics (`Npc.get_choices`) and "Goodbye", or
## moves the topic told on, line by line, in the bubble above their head and in their voice.
## The greeting plays by itself the first time (`Npc.get_greeting`), else the prompt (one of
## theirs, picked for each talk) is said while the list shows. Up and down pick a topic (`step`),
## `interact` plays it or the next line (`press`), `pause` steps back from a topic to the list
## (`leave_topic`) and closes from there. A guest aboard (a co-op player who isn't the host) hears
## a topic's guest lines where it has them, and outside their own room they say its away lines
## (`get_topic_lines`). A topic heard to the end is a flag in the ship's `Story`.
## With "Continue by itself" on (`GameSettings.dialogue_auto_continue`), a topic's line moves on
## by itself after its `VoiceLines.stay_time` (`update`); after the last line the list comes back.
## The card's "Continue" fills up meanwhile; pressing it still moves on at once. Pausing it (the
## card's pause button, or `place_miner`) stops the wait and the voice in the middle of the line
## until it's resumed (the voice goes on where it stopped); moving on (a line, a topic, the list)
## plays normally again.
## Their tour's topics (see `Tour`) start it, go on with it or end it when heard to the end, and
## close the talk.

## Whose talk it is.
var npc: Npc
## The topic being told, or null while the card lists the topics.
var topic: Topic
## The line of `topic` shown.
var line: int = 0
## The highlighted entry of the list: an open topic (`Npc.get_choices`), or after them "Goodbye".
var choice: int = 0
## What they say while the list shows, this talk (the English text, see `Dialogue.pick_prompt`).
var prompt: String = ""
## Whether moving on by itself and the voice are paused (until resumed or the next line).
var auto_paused: bool = false

## How long the line shown waits before it moves on by itself (0: it doesn't), and for how long it
## has waited.
var _line_time: float = 0.0
var _line_waited: float = 0.0


func _init(who: Npc) -> void:
	npc = who


## Starts over at the list as the talk opens, with a new prompt (before the station shows its
## card).
func open() -> void:
	topic = null
	choice = 0
	_set_paused(false)
	var dialogue: Dialogue = npc.profile.dialogue if npc.profile else null
	if dialogue:
		prompt = dialogue.pick_prompt(prompt)


## Plays the greeting while nobody has heard it, else shows the list and says the prompt (once the
## card shows).
func greet() -> void:
	var greeting: Topic = npc.get_greeting()
	if greeting and npc.is_new(greeting):
		talk_about(greeting)
	else:
		_show()
		npc.say(prompt)


## Ends the talk as it closes: no topic, and they stop speaking.
func close() -> void:
	topic = null
	_set_paused(false)
	npc.voice.stop()


## Moves the topic on by itself once the line shown has waited long enough (with auto-continue
## on, not paused), and shows how far it is on the card; each frame while it's open.
func update(delta: float) -> void:
	if get_auto_progress() >= 0.0 and not auto_paused:
		_line_waited += delta
		if _line_waited >= _line_time:
			advance()
	var card_shown := npc.card_menu as TalkCard
	if card_shown:
		card_shown.show_progress(get_auto_progress())


## What their bubble says now (translated): the topic's line, or the prompt while listing.
func get_line() -> String:
	if topic:
		var told: Array[String] = get_topic_lines()
		return npc.tr(told[line]) if line < told.size() else ""
	return npc.tr(prompt) if not prompt.is_empty() else ""


## The lines of the topic being told for the player talking to them (a guest's where it has them,
## the ones for elsewhere outside their own room, see `Topic.lines_for`); none while the list shows.
func get_topic_lines() -> Array[String]:
	if not topic:
		return [] as Array[String]
	return topic.lines_for(npc.is_guest(), npc.routine != null and npc.routine.is_away())


## How far the line shown is towards moving on by itself (0..1, also while paused), or -1 when it
## won't (no topic told, or auto-continue off).
func get_auto_progress() -> float:
	if not topic or _line_time <= 0.0 or not GameSettings.dialogue_auto_continue:
		return -1.0
	return clampf(_line_waited / _line_time, 0.0, 1.0)


## Pauses moving on by itself and the voice in the middle of the line, or resumes both from where
## they stopped (only while it applies, see `get_auto_progress`). Returns whether it did.
func toggle_auto_pause() -> bool:
	if get_auto_progress() < 0.0:
		return false
	_set_paused(not auto_paused)
	npc.refresh()
	return true


## Starts telling `told` from its first line.
func talk_about(told: Topic) -> void:
	topic = told
	line = 0
	if get_topic_lines().is_empty():
		_finish_topic()
	_speak()
	_show()


## Shows the next line; after the last one the topic counts as heard and the list comes back.
func advance() -> void:
	if not topic:
		return
	line += 1
	if line >= get_topic_lines().size():
		_finish_topic()
	_speak()
	_show()


## Does what `interact` does: the next line of the topic, or the highlighted list entry (a topic,
## or "Goodbye", which closes).
func press() -> void:
	if topic:
		advance()
		return
	var choices: Array[Topic] = npc.get_choices()
	if choice < choices.size():
		talk_about(choices[choice])
	else:
		npc.close()


## Highlights list entry `index` (an open topic, or after them "Goodbye").
func set_choice(index: int) -> void:
	choice = clampi(index, 0, npc.get_choices().size())
	_show()


## Up and down move the highlight through the list (left and right do nothing here).
func step(direction: Vector2) -> void:
	if topic or is_zero_approx(direction.y):
		return
	var count: int = npc.get_choices().size() + 1
	set_choice(posmod(choice + int(signf(direction.y)), count))


## Leaves the topic being told for the list (`pause`, "Back"). Returns whether one was told.
func leave_topic() -> bool:
	if not topic:
		return false
	topic = null
	_set_paused(false)
	_show()
	npc.voice.stop()
	return true


## The topic told is heard to the end; a tour's topics then close the talk and start the tour,
## go on with it or end it.
func _finish_topic() -> void:
	var heard: Topic = topic
	npc.get_story().set_flag(heard.id)
	topic = null
	choice = mini(choice, npc.get_choices().size())
	var tour: Tour = npc.profile.tour if npc.profile else null
	if not tour or heard not in [tour.invite, tour.resume, tour.abort]:
		return
	if heard == tour.invite:
		npc.routine.start_tour(npc.user)
	elif heard == tour.abort:
		npc.routine.end_tour()
	npc.close.call_deferred()


## Shows the current state on the card and in the bubble.
func _show() -> void:
	npc.refresh()
	var speech := npc.bubble.content as SpeechBubble
	if speech:
		speech.show_line(get_line())


## Speaks the topic's line shown, or stops when the list is back; starts the line's wait for
## moving on by itself (its `VoiceLines.stay_time`).
func _speak() -> void:
	_set_paused(false)
	var lines: Array[String] = get_topic_lines()
	var told: bool = line < lines.size()
	var recording: AudioStream = npc.say(lines[line] if told else "")
	_line_waited = 0.0
	_line_time = VoiceLines.stay_time(recording, get_line()) if told else 0.0


## Pauses or resumes moving on by itself and the voice.
func _set_paused(paused: bool) -> void:
	auto_paused = paused
	npc.voice.stream_paused = paused
