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
## A quest they offer is told like a topic, then its card shows what it asks and pays (`quest`,
## `offering`): `interact` accepts it, `pause` leaves it for later (it stays offered). A step handed
## in at them shows its card (what's done, what the hold pays of the rest, the rewards), after
## they say its radio calls heard so far again (`QuestCalls.lines`, told like a topic):
## `interact` hands it in, then they say its lines.

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
## The quest whose card shows (instead of the list), or null.
var quest: Quest
## Whether the card offers `quest` (else it hands in its step).
var offering: bool = false

## How long the line shown waits before it moves on by itself (0: it doesn't), and for how long it
## has waited.
var _line_time: float = 0.0
var _line_waited: float = 0.0
## The quest whose radio calls `topic` says again (its card follows), or null.
var _recap: Quest


func _init(who: Npc) -> void:
	npc = who


## Starts over at the list as the talk opens, with a new prompt (before the station shows its
## card).
func open() -> void:
	topic = null
	quest = null
	_recap = null
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
	quest = null
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


## What their bubble says now (translated): the topic's line, the offer's last line while its card
## shows, or the prompt.
func get_line() -> String:
	if quest and offering:
		var offer: Array[String] = quest.offer.lines_for(npc.is_guest(), _is_away())
		return npc.tr(offer[-1]) if not offer.is_empty() else ""
	if topic:
		var told: Array[String] = get_topic_lines()
		return npc.tr(told[line]) if line < told.size() else ""
	return npc.tr(prompt) if not prompt.is_empty() else ""


## The lines of the topic being told for the player talking to them (a guest's where it has them,
## the ones for elsewhere outside their own room, see `Topic.lines_for`); none while the list shows.
func get_topic_lines() -> Array[String]:
	if not topic:
		return [] as Array[String]
	return topic.lines_for(npc.is_guest(), _is_away())


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


## Does what `interact` does: accepts the quest on the card or hands in its step, the next line of
## the topic, or the highlighted list entry (a topic, a quest step's card, or "Goodbye", which
## closes).
func press() -> void:
	if quest:
		_confirm_quest()
		return
	if topic:
		advance()
		return
	var choices: Array[Topic] = npc.get_choices()
	if choice >= choices.size():
		npc.close()
		return
	var quests: QuestLog = npc.get_quests()
	var chosen: Quest = quests.quest_for(choices[choice])
	if chosen and quests.is_accepted(chosen):
		_recap_calls(chosen)
	else:
		talk_about(choices[choice])


## Highlights list entry `index` (an open topic, or after them "Goodbye").
func set_choice(index: int) -> void:
	choice = clampi(index, 0, npc.get_choices().size())
	_show()


## Up and down move the highlight through the list (left and right do nothing here).
func step(direction: Vector2) -> void:
	if topic or quest or is_zero_approx(direction.y):
		return
	var count: int = npc.get_choices().size() + 1
	set_choice(posmod(choice + int(signf(direction.y)), count))


## Leaves the topic being told or the quest's card for the list (`pause`, "Back", "Not now").
## Returns whether one showed.
func leave_topic() -> bool:
	if quest:
		_show_quest(null)
		return true
	if not topic:
		return false
	topic = null
	_recap = null
	_set_paused(false)
	_show()
	npc.voice.stop()
	return true


## The topic told is heard to the end; a quest's offer then shows its card, a tour's topics close
## the talk and start the tour, go on with it or end it.
func _finish_topic() -> void:
	if _recap:
		var recapped: Quest = _recap
		_recap = null
		topic = null
		_show_quest(recapped)
		return
	var heard: Topic = topic
	npc.get_story().set_flag(heard.id)
	topic = null
	choice = mini(choice, npc.get_choices().size())
	var quests: QuestLog = npc.get_quests()
	var offered: Quest = quests.quest_for(heard)
	if offered and not quests.is_accepted(offered):
		_show_quest(offered, true)
		return
	var tour: Tour = npc.profile.tour if npc.profile else null
	if not tour or heard not in [tour.invite, tour.resume, tour.abort]:
		return
	if heard == tour.invite:
		npc.routine.start_tour(npc.user)
	elif heard == tour.abort:
		npc.routine.end_tour()
	npc.close.call_deferred()


## Says the radio calls heard of `accepted`'s active step again (worded for the players in the
## session), then shows its card; at once without any.
func _recap_calls(accepted: Quest) -> void:
	var quests: QuestLog = npc.get_quests()
	var together: bool = npc.get_tree().get_nodes_in_group(Player.GROUP).size() > 1
	var heard: Array[String] = quests.calls.lines(accepted, quests.current_step(accepted), together)
	if heard.is_empty():
		_show_quest(accepted)
		return
	var recap := Topic.new()
	recap.lines = heard
	_recap = accepted
	talk_about(recap)


## Shows the card of `shown` (null: back to the list), `offered` or with its step to hand in.
func _show_quest(shown: Quest, offered: bool = false) -> void:
	quest = shown
	offering = offered
	choice = mini(choice, npc.get_choices().size())
	_show()


## Accepts the quest on the card, or hands in its step (then they say its lines); nothing while
## the step can't be handed in.
func _confirm_quest() -> void:
	var quests: QuestLog = npc.get_quests()
	var players: Array[Player] = []
	players.assign(npc.get_tree().get_nodes_in_group(Player.GROUP))
	if offering:
		quests.accept(quest, players)
		_show_quest(null)
		return
	var handed: QuestStep = quests.current_step(quest)
	if quests.hand_in(quest, npc.user, players):
		quest = null
		talk_about(handed.hand_in)


## Whether they stand outside their own room (for the lines that fit elsewhere).
func _is_away() -> bool:
	return npc.routine != null and npc.routine.is_away()


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
