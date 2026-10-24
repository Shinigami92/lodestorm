extends GutTest
## Talks that continue by themselves (`GameSettings.dialogue_auto_continue`): off by default, a
## voiced line moves on a pause after its voice, one without a voice after its reading time, the
## list comes back after the last line, pressing still moves on at once, the bar on "Continue",
## and the setting on the settings page.

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
