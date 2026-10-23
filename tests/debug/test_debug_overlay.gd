extends GutTest

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const MINER_SETTINGS: String = "res://game/mining/miner_settings.tres"

var _overlay: CanvasLayer
var _map: Node3D
var _mission: Mission
var _voyage: Voyage
var _player: Player


func before_each() -> void:
	_overlay = get_tree().root.get_node("DebugOverlay") as CanvasLayer
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_mission = _map.get_node("Mission") as Mission
	_voyage = _map.get_node("Voyage") as Voyage
	_player = _map.get_node("Player") as Player
	await wait_physics_frames(2)


func after_each() -> void:
	_overlay.call(&"reset_tuning")
	PlayerVitals.god_mode = false
	Alien.ai_on = true
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


func test_god_mode_keeps_players_unhurt_but_kill_still_works() -> void:
	watch_signals(_player.vitals)
	_switch("God mode").button_pressed = true
	_player.take_damage(30.0)
	assert_eq(_player.health, _player.settings.max_health)
	assert_signal_emitted(_player.vitals, "hurt", "the hit still shows")
	_overlay.call(&"kill_players")
	assert_true(_player.dead)
	assert_true(PlayerVitals.god_mode, "stays on")
	_switch("God mode").button_pressed = false
	_player.respawn(_player.global_position)
	_player.take_damage(30.0)
	assert_eq(_player.health, _player.settings.max_health - 30.0)


func test_alien_ai_switch() -> void:
	var switch: CheckButton = _switch("Alien AI")
	assert_true(switch.button_pressed)
	switch.button_pressed = false
	assert_false(Alien.ai_on)
	switch.button_pressed = true
	assert_true(Alien.ai_on)


func test_kill_aliens() -> void:
	assert_gt(get_tree().get_nodes_in_group(Alien.GROUP).size(), 0, "the test map has aliens")
	_overlay.call(&"kill_aliens")
	assert_eq(get_tree().get_nodes_in_group(Alien.GROUP).size(), 0)


func test_whole_number_slider_keeps_integer_setting() -> void:
	var path: String = "res://game/aliens/nest/alien_nest_settings.tres"
	var settings: AlienNestSettings = load(path)
	var slider: HSlider = _overlay.call(&"get_slider", path, "guards")
	slider.value = 3.0
	assert_eq(typeof(settings.get("guards")), TYPE_INT)
	assert_eq(settings.guards, 3)


func test_hatch_hunters() -> void:
	var nests: int = get_tree().get_nodes_in_group(AlienNest.GROUP).size()
	assert_gt(nests, 0, "the test map has nests")
	var nest: AlienNest = _overlay.call(&"_nearest_nest")
	_overlay.call(&"hatch_hunters")
	# The pack hatches one alien after another.
	await wait_physics_frames(roundi(nest.settings.hatch_gap * Engine.physics_ticks_per_second) + 2)
	var hunters: Array[Node] = get_tree().get_nodes_in_group(Alien.GROUP).filter(
		func(alien: Alien) -> bool: return alien.role == Alien.Role.HUNTER
	)
	assert_gte(hunters.size(), 2, "a pack")
	for hunter: Node in hunters:
		assert_true(nest.is_ancestor_of(hunter), "only at the nearest nest")


func test_hatch_raiders() -> void:
	var nest: AlienNest = _overlay.call(&"_nearest_nest")
	_overlay.call(&"hatch_raiders")
	var raiders: Array[Node] = get_tree().get_nodes_in_group(Alien.GROUP).filter(
		func(alien: Alien) -> bool: return alien.role == Alien.Role.RAIDER
	)
	assert_eq(raiders.size(), 1, "one, at the nearest nest")
	assert_true(nest.is_ancestor_of(raiders[0]))


func test_nearest_nest_is_the_one_closest_to_the_player() -> void:
	var player := get_tree().get_first_node_in_group(Player.GROUP) as Player
	var nest: AlienNest = _overlay.call(&"_nearest_nest")
	assert_not_null(nest)
	var closest: float = nest.global_position.distance_to(player.global_position)
	for other: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		assert_gte(other.global_position.distance_to(player.global_position), closest)


func test_break_miners() -> void:
	var node: OreNode = _voyage.location.get_node("OreNodes/KyriteA") as OreNode
	var miner: Miner = node.place_miner(_player.miner_scene)
	_overlay.call(&"break_miners")
	assert_true(miner.broken)


func test_install_shield_opens_the_next_planet() -> void:
	var ship: Ship = _mission.ship
	var before: int = _voyage.offers.size()
	_overlay.call(&"install_shield")
	assert_eq(ship.heat_shield.mk, 2)
	assert_gt(_voyage.offers.size(), before)


func test_refinery_shortcuts() -> void:
	var ship: Ship = _mission.ship
	var cobrel: AlloyType = AlloyCatalog.all().alloys[0]
	_overlay.call(&"_unlock_furnace")
	assert_eq(ship.furnaces.unlocked, 1)
	_overlay.call(&"fill_hold")
	assert_gt(_player.hold.amount(cobrel), 0.0, "the rack too")
	var before: float = _player.hold.amount(cobrel)
	_player.refining.start(0, cobrel, 3, _player.hold, Time.get_unix_time_from_system())
	_overlay.call(&"_finish_refining")
	assert_eq(_player.hold.amount(cobrel), before + 3.0)
	assert_null(_player.refining.get_batch(0))


func test_open_all_offers_every_region() -> void:
	var system: StarSystem = _voyage.settings.system
	var regions: int = 0
	for body: CelestialBody in system.bodies:
		regions += body.regions.size()
	assert_lt(_voyage.offers.size(), regions)
	_overlay.call(&"open_all_bodies")
	assert_eq(_mission.ship.heat_shield.mk, _mission.ship.heat_shield.max_mk())
	assert_eq(_voyage.offers.size(), regions)


func test_buttons_that_would_do_nothing_are_off() -> void:
	_overlay.call(&"toggle")
	await wait_process_frames(2)
	var nest_buttons: Array[Button] = _overlay.get(&"_nest_buttons")
	assert_false(nest_buttons.is_empty())
	assert_false(nest_buttons[0].disabled, "nests to hatch from")
	assert_true((_overlay.get(&"_break_miners_button") as Button).disabled, "no miner")
	for nest: AlienNest in get_tree().get_nodes_in_group(AlienNest.GROUP):
		nest.free()
	for alien: Alien in get_tree().get_nodes_in_group(Alien.GROUP):
		alien.free()
	await wait_process_frames(2)
	for button: Button in nest_buttons:
		assert_true(button.disabled, button.text)
	assert_true((_overlay.get(&"_kill_aliens_button") as Button).disabled, "no aliens")
	_overlay.call(&"toggle")


func test_strain_buttons_show_tier_and_role() -> void:
	var labels: Array[String] = []
	for button: Button in _overlay.get(&"_nest_buttons") as Array[Button]:
		labels.append(button.text)
	assert_has(labels, "Swarmer (T1, Hunter)")
	assert_has(labels, "Spitter (T2, Hunter)")
	assert_has(labels, "Warden (T1, Guard)")
	assert_has(labels, "Gnawer (T1, Raider)")
	var tiers: Array[int] = []
	for label: String in labels:
		var at: int = label.find("(T")
		if at >= 0:
			tiers.append(label.substr(at + 2, 1).to_int())
	var sorted: Array[int] = tiers.duplicate()
	sorted.sort()
	assert_eq(tiers, sorted, "by tier")


## The overlay's switch labeled `text`.
func _switch(text: String) -> CheckButton:
	for button: Node in _overlay.find_children("*", "CheckButton", true, false):
		if (button as CheckButton).text == text:
			return button
	return null
