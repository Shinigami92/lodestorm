class_name PlayerRadio
extends Node3D
## The radio in a player's suit (see GAME_DESIGN.md, Story and setting: how it's told): a crew
## member's call (see `CrewReactions.call_radio`) shows in a bubble beside the player's head
## (`Bubble`, a `RadioBubble`), to its left on screen, clear of what floats above the player, grown
## with the camera's view like the colonists' bubbles. It stays as long as a line moving on by
## itself (its voice and `Npc.AUTO_PAUSE`, else `Npc.reading_time`) and never blocks. Calls coming
## in meanwhile wait their turn (`GAP` s apart); a newer call about the same thing replaces one
## still waiting. The local player also hears it, on the Radio bus (its filter makes it sound like
## a radio).

const PANEL_SCENE: PackedScene = preload("res://game/ui/world_panel.tscn")
const BUBBLE_SCENE: PackedScene = preload("res://game/npcs/radio_bubble.tscn")
## The bubble's size (in m at the normal view) and resolution.
const SIZE := Vector2(1.6, 0.8)
const PIXELS_PER_METER: float = 450.0
## Where the bubble's lower right corner sits: this high above the player's feet and this far left
## of the player on screen, in m at the normal view.
const HEIGHT: float = 1.9
const SIDE_GAP: float = 0.35
## The pause between two calls, in s. TBD (playtest).
const GAP: float = 1.0

## Whose radio it is.
var holder: Player
## The bubble beside the player.
var panel: WorldPanel
## Plays the call's recording for the local player.
var voice: AudioStreamPlayer

var _left: float = 0.0
## How long until the next waiting call may start, in s.
var _gap_left: float = 0.0
## Calls waiting their turn: [caller, English line, what it's about], oldest first.
var _waiting: Array[Array] = []


func _ready() -> void:
	panel = PANEL_SCENE.instantiate() as WorldPanel
	panel.name = "Bubble"
	panel.menu = BUBBLE_SCENE
	panel.size = SIZE
	panel.pixels_per_meter = PIXELS_PER_METER
	panel.transparent = true
	add_child(panel)
	panel.visible = false
	# Only shows for a moment: over the walls and props in front of the player.
	panel.set_on_top(true)
	voice = AudioStreamPlayer.new()
	voice.name = "Voice"
	voice.bus = &"Radio"
	add_child(voice)


func _process(delta: float) -> void:
	if not panel.visible:
		_gap_left -= delta
		if _gap_left <= 0.0 and not _waiting.is_empty():
			var call_waiting: Array = _waiting.pop_front()
			_play(call_waiting[0] as NpcProfile, call_waiting[1] as String)
		return
	_left -= delta
	if _left <= 0.0:
		panel.visible = false
		_gap_left = GAP
		return
	_place()


## Shows `english` (a line's English text) as a call from `caller` about `topic`, and plays its
## recording for the local player: at once, or after the calls before it.
func hear(caller: NpcProfile, english: String, topic: StringName = &"") -> void:
	if not panel.visible and _waiting.is_empty() and _gap_left <= 0.0:
		_play(caller, english)
		return
	if not topic.is_empty():
		for queued: Array in _waiting.duplicate():
			if queued[2] == topic:
				_waiting.erase(queued)
	_waiting.append([caller, english, topic])


## How many calls wait their turn.
func waiting_count() -> int:
	return _waiting.size()


## Ends the call showing and drops the waiting ones.
func clear() -> void:
	_waiting.clear()
	_gap_left = 0.0
	_left = 0.0
	panel.visible = false
	voice.stop()


func _play(caller: NpcProfile, english: String) -> void:
	var bubble := panel.content as RadioBubble
	var text: String = tr(english)
	if bubble:
		bubble.show_call(caller.display_name, caller.accent_color, text)
	panel.visible = true
	voice.stop()
	var recording: AudioStream = VoiceLines.stream(caller.id, english) if holder.local else null
	if recording:
		voice.stream = recording
		voice.play()
	_left = recording.get_length() + Npc.AUTO_PAUSE if recording else Npc.reading_time(text)
	_place()


## The call showing (translated), or "".
func get_line() -> String:
	var bubble := panel.content as RadioBubble
	return bubble.get_line() if bubble and panel.visible else ""


## Keeps the bubble left of the player's head on screen, facing the camera, grown with the view;
## unchanged without a camera (or outside the tree).
func _place() -> void:
	if not is_inside_tree():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return
	var factor: float = SpeechBubble.view_scale(get_tree())
	var view: Basis = camera.global_basis.orthonormalized()
	var corner: Vector3 = holder.global_position + Vector3.UP * HEIGHT
	var middle: Vector3 = (
		corner - view.x * (SIZE.x * 0.5 + SIDE_GAP) * factor + view.y * SIZE.y * 0.5 * factor
	)
	panel.global_transform = Transform3D(view.scaled_local(Vector3.ONE * factor), middle)
