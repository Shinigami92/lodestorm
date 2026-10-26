extends GutTest
## Talks that continue by themselves (`GameSettings.dialogue_auto_continue`): off by default, a
## voiced line moves on a pause after its voice, one without a voice after its reading time, the
## list comes back after the last line, pressing still moves on at once, the bar on "Continue",
## pausing and resuming it (the card's pause button, `place_miner`), and the setting on the
## settings page.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const SETTINGS_LIST: PackedScene = preload("res://game/ui/settings_list.tscn")
const DIRECTORY: String = "user://test_npc_auto_continue/"

var _map: Node3D
var _player: Player
var _npc: Npc


func before_each() -> void:
	GameSettings.voice_language = ""
	GameSettings.dialogue_auto_continue = false
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_npc = _map.get_node("Ship/Rooms/Lower/Armory/Quartermaster") as Npc
	await wait_physics_frames(2)


func after_each() -> void:
	GameSettings.voice_language = ""
	GameSettings.dialogue_auto_continue = false
	if SaveGame.directory:
		DirAccess.remove_absolute(GameSettings.path())
		SaveGame.directory = ""


func test_off_by_default_a_line_waits_for_the_player() -> void:
	_npc.open(_player)
	assert_not_null(_npc.topic, "the greeting")
	_wait(600.0)
	assert_eq(_npc.line, 0, "still the first line")
	assert_eq(_npc.get_auto_progress(), -1.0)
	assert_false(_bar_shown())
	_npc.close()


func test_a_voiced_line_moves_on_a_pause_after_its_voice() -> void:
	GameSettings.dialogue_auto_continue = true
	_npc.open(_player)
	var recording := _npc.voice.stream
	assert_not_null(recording, "the quartermaster's greeting is voiced")
	var wait: float = recording.get_length() + Npc.AUTO_PAUSE
	_wait(wait - 0.1)
	assert_eq(_npc.line, 0, "the voice and the pause first")
	assert_almost_eq(_npc.get_auto_progress(), (wait - 0.1) / wait, 0.01)
	assert_true(_bar_shown(), "the bar on Continue fills")
	_wait(0.2)
	assert_eq(_npc.line, 1, "the next line")
	assert_almost_eq(_npc.get_auto_progress(), 0.0, 0.05, "its own wait starts")
	_npc.close()


func test_without_a_voice_a_line_stays_its_reading_time() -> void:
	GameSettings.dialogue_auto_continue = true
	GameSettings.voice_language = VoiceLines.OFF
	_npc.open(_player)
	var wait: float = Npc.reading_time(_npc.get_line())
	assert_almost_eq(wait, Npc.READ_BASE + Npc.READ_PER_LETTER * _npc.get_line().length(), 0.001)
	_wait(wait - 0.1)
	assert_eq(_npc.line, 0)
	_wait(0.2)
	assert_eq(_npc.line, 1)
	_npc.close()


func test_after_the_last_line_the_list_comes_back() -> void:
	GameSettings.dialogue_auto_continue = true
	GameSettings.voice_language = VoiceLines.OFF
	_npc.open(_player)
	var greeting: Topic = _npc.topic
	for i: int in greeting.lines.size():
		_wait(Npc.reading_time(_npc.get_line()) + 0.1)
	assert_null(_npc.topic, "the list")
	assert_true(_npc.get_story().is_set(greeting.id), "heard to the end")
	assert_false(_bar_shown(), "no bar on the list")
	_wait(600.0)
	assert_null(_npc.topic, "the list stays")
	_npc.close()


func test_pressing_still_moves_on_at_once() -> void:
	GameSettings.dialogue_auto_continue = true
	GameSettings.voice_language = VoiceLines.OFF
	_npc.open(_player)
	_wait(1.0)
	_npc.press()
	assert_eq(_npc.line, 1, "skipped")
	assert_almost_eq(_npc.get_auto_progress(), 0.0, 0.01, "the new line waits its own time")
	_wait(Npc.reading_time(_npc.get_line()) - 0.1)
	assert_eq(_npc.line, 1)
	_npc.close()


func test_pausing_holds_the_line_and_the_voice_until_resumed() -> void:
	GameSettings.dialogue_auto_continue = true
	_npc.open(_player)
	await wait_process_frames(2)
	var card := _npc.card_menu as TalkCard
	var pause: Button = card.get_pause_button()
	assert_true(pause.visible, "beside Continue while the line moves on by itself")
	assert_eq(pause.icon, TalkCard.PAUSE_ICON)
	assert_almost_eq(pause.size.x, pause.size.y, 1.0, "square")
	var row: Control = pause.get_parent() as Control
	assert_eq(row, card.get_button("Continue").get_parent(), "in Continue's row")
	assert_not_null(_npc.voice.stream, "the greeting is voiced")
	_wait(1.0)
	pause.pressed.emit()
	assert_true(_npc.auto_paused)
	assert_true(_npc.voice.stream_paused, "the voice stops in the middle of the line")
	assert_eq(pause.icon, TalkCard.PLAY_ICON, "shows play while paused")
	var held: float = _npc.get_auto_progress()
	_wait(600.0)
	assert_eq(_npc.line, 0, "the line stays")
	assert_almost_eq(_npc.get_auto_progress(), held, 0.001, "the bar stops")
	_press(&"place_miner")
	assert_false(_npc.auto_paused, "the key resumes it")
	assert_false(_npc.voice.stream_paused, "the voice goes on where it stopped")
	assert_eq(pause.icon, TalkCard.PAUSE_ICON)
	_press(&"place_miner")
	assert_true(_npc.auto_paused, "the key pauses it too")
	_npc.press()
	assert_eq(_npc.line, 1, "Continue still moves on")
	assert_false(_npc.auto_paused, "and the next line plays normally")
	assert_false(_npc.voice.stream_paused)
	assert_eq(pause.icon, TalkCard.PAUSE_ICON)
	_wait(_npc.voice.stream.get_length() + Npc.AUTO_PAUSE + 0.1)
	assert_eq(_npc.line, 2, "goes on by itself again")
	pause.pressed.emit()
	_npc.close()
	assert_false(_npc.voice.stream_paused)
	_npc.open(_player)
	assert_false(_npc.auto_paused, "a new talk starts unpaused")
	_npc.close()


func test_no_pause_button_without_auto_continue_or_on_the_list() -> void:
	_npc.open(_player)
	await wait_process_frames(2)
	var card := _npc.card_menu as TalkCard
	assert_false(card.get_pause_button().visible, "auto-continue off")
	_press(&"place_miner")
	assert_false(_npc.auto_paused, "nothing to pause")
	_npc.close()
	GameSettings.dialogue_auto_continue = true
	_npc.get_story().set_flag(_npc.profile.dialogue.greeting.id)
	_npc.open(_player)
	await wait_process_frames(2)
	assert_null(_npc.topic, "the list")
	assert_false(card.get_pause_button().visible, "nothing moves on by itself on the list")
	_npc.close()


func test_picked_in_the_settings_and_saved() -> void:
	SaveGame.directory = DIRECTORY
	var list := SETTINGS_LIST.instantiate() as SettingsList
	add_child_autofree(list)
	var box := list.get_node("%AutoContinue") as CheckBox
	assert_false(box.button_pressed, "off by default")
	box.button_pressed = true
	assert_true(GameSettings.dialogue_auto_continue)
	GameSettings.dialogue_auto_continue = false
	GameSettings.load_settings()
	assert_true(GameSettings.dialogue_auto_continue, "saved")


## Runs the talk's clock on by `seconds`, in frame-sized steps.
func _wait(seconds: float) -> void:
	var step: float = 1.0 / 60.0
	var left: float = seconds
	while left > 0.0:
		_npc._auto_continue(minf(step, left))
		left -= step


func _bar_shown() -> bool:
	var bar: ColorRect = (_npc.card_menu as TalkCard).get_progress_bar()
	return bar != null and bar.visible


## Presses and releases `action` as an input event.
func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		get_viewport().push_input(event)
