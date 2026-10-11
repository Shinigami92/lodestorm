extends GutTest

const TEST_MAP: PackedScene = preload("res://scenes/maps/test_map.tscn")
const MINER_SETTINGS: String = "res://scenes/mining/miner_settings.tres"

var _overlay: CanvasLayer
var _map: Node3D
var _mission: Mission
var _player: Player


func before_each() -> void:
	_overlay = get_tree().root.get_node("DebugOverlay") as CanvasLayer
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_mission = _map.get_node("Mission") as Mission
	_player = _map.get_node("Player") as Player
	await wait_physics_frames(2)


func after_each() -> void:
	_overlay.call(&"reset_tuning")
	_overlay.visible = false


func test_exists_when_run_from_editor() -> void:
	assert_true(OS.has_feature("editor"))
	assert_not_null(_overlay)


func test_hidden_until_toggled() -> void:
	assert_false(_overlay.visible)
	var press := InputEventAction.new()
	press.action = &"debug_overlay"
	press.pressed = true
	Input.parse_input_event(press)
	await wait_process_frames(2)
	assert_true(_overlay.visible)
	_overlay.call(&"toggle")
	assert_false(_overlay.visible)


func test_slider_tunes_settings_live() -> void:
	var settings: MinerSettings = load(MINER_SETTINGS)
	var default_rate: float = settings.fill_rate
	var slider: HSlider = _overlay.call(&"get_slider", MINER_SETTINGS, "fill_rate")
	assert_eq(slider.value, default_rate)
	slider.value = 7.5
	assert_eq(settings.fill_rate, 7.5)
	_overlay.call(&"reset_tuning")
	assert_eq(settings.fill_rate, default_rate)


func test_storm_shortcuts_need_running_timer() -> void:
	_overlay.call(&"start_storm")
	assert_eq(_mission.time_left, _mission.settings.duration, "no effect before the start")
	_mission.state = Mission.State.RUNNING
	_overlay.call(&"skip_to_warning")
	assert_eq(_mission.time_left, _mission.settings.warning_time)
	_overlay.call(&"start_storm")
	assert_eq(_mission.time_left, 0.0)


func test_kill_and_heal_players() -> void:
	_player.take_damage(10.0)
	_overlay.call(&"heal_players")
	assert_eq(_player.health, _player.settings.max_health)
	_overlay.call(&"kill_players")
	assert_true(_player.dead)


func test_kill_aliens() -> void:
	assert_gt(get_tree().get_nodes_in_group(Alien.GROUP).size(), 0, "the test map has aliens")
	_overlay.call(&"kill_aliens")
	assert_eq(get_tree().get_nodes_in_group(Alien.GROUP).size(), 0)


func test_whole_number_slider_keeps_integer_setting() -> void:
	var path: String = "res://scenes/aliens/alien_nest_settings.tres"
	var settings: AlienNestSettings = load(path)
	var slider: HSlider = _overlay.call(&"get_slider", path, "max_hunters_end")
	slider.value = 7.0
	assert_eq(typeof(settings.get("max_hunters_end")), TYPE_INT)
	assert_eq(settings.max_hunters_end, 7)


func test_hatch_hunters() -> void:
	var nests: int = get_tree().get_nodes_in_group(AlienNest.GROUP).size()
	assert_gt(nests, 0, "the test map has nests")
	_overlay.call(&"hatch_hunters")
	var hunters: Array[Node] = get_tree().get_nodes_in_group(Alien.GROUP).filter(
		func(alien: Alien) -> bool: return alien.role == Alien.Role.HUNTER
	)
	assert_eq(hunters.size(), nests)


func test_hatch_raiders() -> void:
	var nests: int = get_tree().get_nodes_in_group(AlienNest.GROUP).size()
	_overlay.call(&"hatch_raiders")
	var raiders: Array[Node] = get_tree().get_nodes_in_group(Alien.GROUP).filter(
		func(alien: Alien) -> bool: return alien.role == Alien.Role.RAIDER
	)
	assert_eq(raiders.size(), nests)


func test_break_miners() -> void:
	var node: OreNode = _mission.location.get_node("OreNodes/CyanA") as OreNode
	var miner: Miner = node.place_miner(_player.miner_scene)
	_overlay.call(&"break_miners")
	assert_true(miner.broken)
