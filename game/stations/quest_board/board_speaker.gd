class_name BoardSpeaker
extends AudioStreamPlayer3D
## The quest board's speaker (see `QuestBoardStation`): plays a message on the Messages tab aloud,
## its lines one after another in its sender's voice (`VoiceLines`), a line without a recording for
## its reading time. Played to the end, the message is heard (`MessageLog.hear`).

## The message playing, or null.
var playing_entry: ReceivedMessage
## The log it's noted heard in.
var messages: MessageLog
## The line playing (its index).
var line: int = -1

var _left: float = 0.0


func _init() -> void:
	bus = &"Voice"
	# It carries like a voice close by.
	unit_size = Npc.VOICE_UNIT_SIZE
	max_distance = Npc.VOICE_MAX_DISTANCE


func _process(delta: float) -> void:
	if not playing_entry:
		return
	_left -= delta
	if _left <= 0.0:
		_say(line + 1)


## Plays `entry` (of `in_log`) from its first line, stopping what played before.
func play_message(entry: ReceivedMessage, in_log: MessageLog) -> void:
	playing_entry = entry
	messages = in_log
	_say(0)


## Stops the message playing (it isn't heard then).
func stop_message() -> void:
	stop()
	playing_entry = null
	line = -1


## Says line `index` of the message playing; past the last one, it's heard and stops.
func _say(index: int) -> void:
	stop()
	var lines: Array[String] = playing_entry.message.lines
	if index >= lines.size():
		if messages:
			messages.hear(playing_entry)
		stop_message()
		return
	line = index
	var english: String = lines[index]
	var recording: AudioStream = VoiceLines.stream(playing_entry.message.from, english)
	if recording:
		stream = recording
		play()
	_left = VoiceLines.stay_time(recording, tr(english))
