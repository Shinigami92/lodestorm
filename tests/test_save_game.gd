extends GutTest

const TEST_MAP := preload("res://tests/support/test_map.gd")
const SETTINGS_MENU: PackedScene = preload("res://scenes/ui/settings_menu.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const BLASTER: WeaponType = preload("res://scenes/weapons/types/blaster.tres")
const SHOTGUN: WeaponType = preload("res://scenes/weapons/types/shotgun.tres")
const HAMMER: WeaponType = preload("res://scenes/weapons/types/hammer.tres")
const ARMOR: Upgrade = preload("res://scenes/upgrades/armor.tres")
const DRILL: Upgrade = preload("res://scenes/upgrades/miner_drill.tres")
const SUIT: Skill = preload("res://scenes/skills/reinforced_suit.tres")
const DASH: Skill = preload("res://scenes/skills/dash.tres")
const CYAN: OreType = preload("res://scenes/mining/ores/ore_cyan.tres")
const GREEN: OreType = preload("res://scenes/mining/ores/ore_green.tres")
const DIRECTORY: String = "user://test_save/"
## A local port for hosting a session in the tests.
const HOST_PORT: int = 47913

var _map: Node3D
var _player: Player
var _mission: Mission
var _ship: Ship


func before_each() -> void:
	SaveGame.directory = DIRECTORY
	_clean()
	await _start()


func after_each() -> void:
	_clean()
	SaveGame.directory = ""


func test_fresh_start_without_save() -> void:
	assert_false(SaveGame.exists())
	assert_true(_ship.hold.is_empty())
	assert_eq(_player.upgrades.mk(ARMOR), 1)


func test_progress_survives_a_restart() -> void:
	_ship.add_to_hold(CYAN, 120.5)
	_ship.add_to_hold(GREEN, 40.0)
	_player.arsenal.unlock(SHOTGUN)
	_player.loadout.assign(0, SHOTGUN)
	_player.loadout.assign(1, null)
	_player.upgrades.raise(ARMOR)
	_player.upgrades.raise(DRILL)
	_player.upgrades.raise(DRILL)
	await wait_process_frames(1)
	assert_true(SaveGame.exists(), "saved right away")
	await _restart()
	assert_eq(_ship.hold[CYAN], 120.5)
	assert_eq(_ship.hold[GREEN], 40.0)
	assert_eq(_player.arsenal.weapons, [BLASTER, HAMMER, SHOTGUN] as Array[WeaponType])
	assert_eq(_player.loadout.get_weapon(0), SHOTGUN)
	assert_null(_player.loadout.get_weapon(1))
	assert_eq(_player.get_weapon_type(), SHOTGUN)
	assert_eq(_player.upgrades.mk(ARMOR), 2)
	assert_eq(_player.upgrades.mk(DRILL), 3)
	assert_eq(_player.health, _player.max_health(), "full health with the saved armor")
	assert_gt(_player.max_health(), _player.settings.max_health)


func test_skills_survive_a_restart() -> void:
	_player.skills.raise(SUIT)
	_player.skills.raise(SUIT)
	_player.skills.raise(DASH)
	await wait_process_frames(1)
	await _restart()
	assert_eq(_player.skills.rank(SUIT), 2)
	assert_eq(_player.skills.rank(DASH), 1)
	assert_eq(_player.health, _player.max_health(), "full health with the saved skills")


func test_story_survives_a_restart() -> void:
	_ship.story.set_flag(&"quartermaster.greeting")
	_ship.story.set_flag(&"quartermaster.ammo")
	await wait_process_frames(1)
	await _restart()
	assert_true(_ship.story.is_set(&"quartermaster.greeting"))
	assert_true(_ship.story.is_set(&"quartermaster.ammo"))
	assert_eq(_ship.story.flags.size(), 2)


func test_mission_progress_is_saved_when_it_is_over() -> void:
	_ship.add_to_hold(CYAN, 10.0)
	await wait_process_frames(1)
	_ship.ramp_duration = 0.25
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_physics_frames(ceili(_ship.ramp_duration * Engine.physics_ticks_per_second) + 2)
	assert_true(_mission.is_underway())
	await _move(_ship.to_global(Vector3(22.0, 0.0, 0.0)))
	_player.add_cargo(CYAN, 100.0)
	_ship.add_to_hold(GREEN, 5.0)
	await wait_process_frames(1)
	assert_eq(_saved_hold(CYAN), 10.0, "nothing saved mid-mission")
	await _move(_ship.to_global(Vector3(10.0, 2.5, 0.0)))
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_eq(_saved_hold(CYAN), 110.0, "saved once everyone is back")
	assert_eq(_saved_hold(GREEN), 5.0)


func test_quitting_mid_mission_loses_the_run() -> void:
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_physics_frames(2)
	_ship.add_to_hold(CYAN, 50.0)
	await _restart()
	assert_false(_ship.hold.has(CYAN))


func test_unreadable_save_starts_fresh_and_is_kept() -> void:
	_write(SaveGame.PLAYER_FILE, "{ not json")
	await _restart()
	assert_push_error("can't read")
	assert_eq(_player.arsenal.weapons, [BLASTER, HAMMER] as Array[WeaponType])
	var corrupt: String = SaveGame.save_directory().path_join(SaveGame.PLAYER_FILE + ".corrupt")
	assert_true(FileAccess.file_exists(corrupt))


func test_newer_save_is_not_read() -> void:
	_write(SaveGame.SHIP_FILE, JSON.stringify({"version": SaveGame.VERSION + 1, "hold": {}}))
	await _restart()
	assert_push_error("can't read")


func test_unknown_entries_are_skipped() -> void:
	var ship_data: Dictionary = {
		"version": SaveGame.VERSION,
		"hold":
		{
			CYAN.resource_path: 30.0,
			"res://nothing.tres": 5.0,
			"user://ore.tres": 5.0,
			SHOTGUN.resource_path: 5.0,
			GREEN.resource_path: -4.0,
		},
		"story": ["quartermaster.ammo", 3, ""],
	}
	var player_data: Dictionary = {
		"version": SaveGame.VERSION,
		"arsenal": [BLASTER.resource_path, "res://nothing.tres", 3, CYAN.resource_path],
		"loadout": [HAMMER.resource_path, SHOTGUN.resource_path],
		"upgrades": {ARMOR.resource_path: 99, "res://nothing.tres": 2, DRILL.resource_path: "x"},
		"skills": {SUIT.resource_path: 99, ARMOR.resource_path: 1, DASH.resource_path: 0},
	}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	assert_eq(_ship.hold.keys(), [CYAN] as Array[OreType])
	assert_eq(_ship.story.flags.keys(), [&"quartermaster.ammo"] as Array[StringName])
	assert_eq(_player.arsenal.weapons, [BLASTER] as Array[WeaponType])
	assert_null(_player.loadout.get_weapon(0), "not owned")
	assert_null(_player.loadout.get_weapon(1), "not owned")
	assert_eq(_player.upgrades.mk(ARMOR), ARMOR.max_mk(), "clamped")
	assert_eq(_player.upgrades.mk(DRILL), 1)
	assert_eq(_player.skills.rank(SUIT), SUIT.max_rank(), "clamped")
	assert_eq(_player.skills.ranks.size(), 1, "not a skill, rank 0")


func test_language_is_saved_apart_from_progress() -> void:
	assert_eq(GameSettings.saved_language(), "")
	GameSettings.set_language("de")
	TranslationServer.set_locale("en")
	assert_eq(GameSettings.saved_language(), "de")
	_player.upgrades.raise(ARMOR)
	await wait_process_frames(1)
	SaveGame.erase()
	assert_false(SaveGame.exists())
	assert_eq(GameSettings.saved_language(), "de", "resetting keeps the settings")


func test_reset_asks_three_times() -> void:
	_player.upgrades.raise(ARMOR)
	await wait_process_frames(1)
	var menu := SETTINGS_MENU.instantiate() as SettingsMenu
	menu.confirm_delay = 0.1
	add_child_autofree(menu)
	var reset: Button = menu.get_node("%ResetProgress")
	var confirm: Button = menu.get_wipe_confirm_button()
	var warning: Label = menu.get_node("%WipeWarning")
	reset.pressed.emit()
	for step: int in [1, 2, 3]:
		assert_eq(menu.wipe_step, step)
		assert_string_contains(confirm.text, "%d/3" % step)
		assert_ne(warning.text, "", "warns that it wipes the progress for good")
		assert_true(confirm.disabled, "can't be pressed right away")
		confirm.pressed.emit()
		assert_eq(menu.wipe_step, step, "ignored before the delay")
		assert_true(SaveGame.exists(), "nothing wiped before the last answer")
		await wait_seconds(0.2)
		assert_false(confirm.disabled)
		confirm.pressed.emit()
	assert_false(SaveGame.exists(), "wiped")
	assert_eq(menu.wipe_step, 0)


func test_cancel_keeps_the_progress() -> void:
	_player.upgrades.raise(ARMOR)
	await wait_process_frames(1)
	var menu := SETTINGS_MENU.instantiate() as SettingsMenu
	menu.confirm_delay = 0.0
	add_child_autofree(menu)
	(menu.get_node("%ResetProgress") as Button).pressed.emit()
	await wait_process_frames(1)
	menu.get_wipe_confirm_button().pressed.emit()
	await wait_process_frames(1)
	(menu.get_node("%WipeCancel") as Button).pressed.emit()
	assert_eq(menu.wipe_step, 0)
	assert_true((menu.get_node("%ResetProgress") as Button).visible)
	assert_true(SaveGame.exists())


func test_reset_only_in_solo_play() -> void:
	_player.upgrades.raise(ARMOR)
	await wait_process_frames(1)
	var menu := SETTINGS_MENU.instantiate() as SettingsMenu
	menu.confirm_delay = 0.0
	add_child_autofree(menu)
	var reset: Button = menu.get_node("%ResetProgress")
	var hint: Label = menu.get_node("%ResetHint")
	await wait_process_frames(1)
	assert_false(reset.disabled)
	assert_false(hint.visible)
	var guest := PLAYER_SCENE.instantiate() as Player
	_map.add_child(guest)
	await wait_process_frames(1)
	assert_false(SaveGame.is_solo(get_tree()))
	assert_true(reset.disabled, "co-op: everyone keeps their progress")
	assert_true(hint.visible, "says why")
	reset.pressed.emit()
	assert_eq(menu.wipe_step, 0)
	var save_game: SaveGame = _map.get_node("SaveGame")
	assert_false(save_game.reset_progress())
	assert_true(SaveGame.exists())
	guest.free()
	await wait_process_frames(1)
	assert_false(reset.disabled, "solo again")
	assert_false(hint.visible)


func test_hosting_alone_counts_as_solo() -> void:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	assert_eq(peer.create_server(HOST_PORT), OK)
	var multiplayer_api: MultiplayerAPI = get_tree().get_multiplayer()
	multiplayer_api.multiplayer_peer = peer
	await wait_process_frames(1)
	assert_true(SaveGame.is_solo(get_tree()), "open for friends to join, but alone")
	multiplayer_api.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer.close()


func test_co_op_drops_the_reset_question() -> void:
	var menu := SETTINGS_MENU.instantiate() as SettingsMenu
	add_child_autofree(menu)
	(menu.get_node("%ResetProgress") as Button).pressed.emit()
	assert_eq(menu.wipe_step, 1)
	var guest := PLAYER_SCENE.instantiate() as Player
	_map.add_child(guest)
	await wait_process_frames(2)
	assert_eq(menu.wipe_step, 0)
	assert_false((menu.get_node("%Wipe") as Control).visible)
	guest.free()


func _start() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_mission = _map.get_node("Mission") as Mission
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func _restart() -> void:
	_map.free()
	await _start()


func _move(target: Vector3) -> void:
	_player.global_position = target
	_player.reset_physics_interpolation()
	await wait_physics_frames(5)


func _saved_hold(ore_type: OreType) -> float:
	var path: String = SaveGame.save_directory().path_join(SaveGame.SHIP_FILE)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var hold: Dictionary = data["hold"]
	return hold.get(ore_type.resource_path, 0.0)


func _write(file_name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SaveGame.save_directory())
	var file := FileAccess.open(SaveGame.save_directory().path_join(file_name), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean() -> void:
	SaveGame.erase()
	if FileAccess.file_exists(GameSettings.path()):
		DirAccess.remove_absolute(GameSettings.path())
