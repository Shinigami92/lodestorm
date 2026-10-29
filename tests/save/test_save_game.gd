extends GutTest

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const SETTINGS_MENU: PackedScene = preload("res://game/ui/settings_menu.tscn")
const PLAYER_SCENE: PackedScene = preload("res://game/player/player.tscn")
const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")
const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const SUIT: Skill = preload("res://game/progression/skills/tree/reinforced_suit.tres")
const DASH: Skill = preload("res://game/progression/skills/tree/dash.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")
const COBREL: AlloyType = preload("res://game/refinery/alloys/alloy_cobrel.tres")
const MERISK: AlloyType = preload("res://game/refinery/alloys/alloy_merisk.tres")
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
	assert_true(_player.hold.items.is_empty())
	assert_eq(_player.upgrades.mk(ARMOR), 1)


func test_progress_survives_a_restart() -> void:
	_player.hold.add(KYRITE, 120.5)
	_player.hold.add(OLVANE, 40.0)
	_player.arsenal.unlock(BRASK)
	_player.loadout.assign(0, BRASK)
	_player.loadout.assign(1, null)
	_player.upgrades.raise(ARMOR)
	_player.fleet.get_miner(1).upgrades.raise(DRILL)
	_player.fleet.get_miner(1).upgrades.raise(DRILL)
	_player.fleet.get_miner(1).going_along = false
	_player.fleet.start_build(2, Time.get_unix_time_from_system(), 600.0)
	await wait_process_frames(1)
	assert_true(SaveGame.exists(), "saved right away")
	await _restart()
	assert_eq(_player.hold.amount(KYRITE), 120.5)
	assert_eq(_player.hold.amount(OLVANE), 40.0)
	assert_eq(_player.arsenal.weapons, [HARL, DRAY, BRASK] as Array[WeaponType])
	assert_eq(_player.loadout.get_weapon(0), BRASK)
	assert_null(_player.loadout.get_weapon(1))
	assert_eq(_player.arms.get_weapon_type(), BRASK)
	assert_eq(_player.upgrades.mk(ARMOR), 2)
	var first: CraftedMiner = _player.fleet.get_miner(1)
	assert_eq(first.upgrades.mk(DRILL), 3)
	assert_false(first.going_along)
	assert_false(_player.fleet.get_miner(2).is_built(), "still being built")
	assert_true(_player.fleet.is_empty(3))
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


func test_jobs_under_way_survive_a_restart() -> void:
	var now: float = Time.get_unix_time_from_system()
	_player.upgrades.start(ARMOR, now - 10.0)
	_player.fleet.get_miner(1).upgrades.start(DRILL, now - 3600.0)
	_player.fleet.start_build(2, now - 3600.0, 600.0)
	_player.skills.start(DASH, now)
	_player.skills.jobs[DASH].seconds = 600.0
	await wait_process_frames(1)
	var saved: Dictionary = _saved("player.json")
	var upgrades: Dictionary = saved["upgrades"]
	assert_eq((upgrades["jobs"] as Dictionary).size(), 1)
	await _restart()
	assert_true(_player.upgrades.is_running(ARMOR), "a minute takes longer than 10 s")
	# JSON keeps the Unix time to well under a millisecond, not to the last bit on every platform.
	assert_almost_eq(_player.upgrades.get_job(ARMOR).started, now - 10.0, 0.001)
	assert_eq(_player.upgrades.get_job(ARMOR).seconds, ARMOR.levels[0].seconds)
	var first: CraftedMiner = _player.fleet.get_miner(1)
	assert_false(first.upgrades.is_running(DRILL), "done while the game was closed")
	assert_eq(first.upgrades.mk(DRILL), 2)
	assert_true(_player.fleet.get_miner(2).is_built(), "built meanwhile")
	assert_eq(_player.skills.get_job(DASH).seconds, 600.0, "its time as it started")
	assert_eq(_player.skills.rank(DASH), 0)


## A job under way keeps what was paid for it, so stopping it after a restart gives that back.
func test_jobs_keep_what_was_paid() -> void:
	var paid: Dictionary[ItemType, int] = {KYRITE: 100, MERISK: 4}
	_player.upgrades.restore(ARMOR, TimedJob.new(2, 1e12, 60.0, paid))
	_player.fleet.start_build(2, 1e12, 60.0, {COBREL: 3})
	await wait_process_frames(1)
	var saved: Dictionary = _saved(SaveGame.PLAYER_FILE)
	var upgrades: Dictionary = saved["upgrades"]
	var job: Dictionary = (upgrades["jobs"] as Dictionary)[_uid(ARMOR)]
	var saved_paid: Dictionary = job["paid"]
	assert_eq(saved_paid, {_uid(KYRITE): 100.0, _uid(MERISK): 4.0})
	await _restart()
	assert_eq(_player.upgrades.stop(ARMOR), paid)
	assert_eq(_player.fleet.get_miner(2).build.paid, {COBREL: 3} as Dictionary[ItemType, int])


func test_story_survives_a_restart() -> void:
	_ship.story.set_flag(&"quartermaster.greeting")
	_ship.story.set_flag(&"quartermaster.ammo")
	await wait_process_frames(1)
	await _restart()
	assert_true(_ship.story.is_set(&"quartermaster.greeting"))
	assert_true(_ship.story.is_set(&"quartermaster.ammo"))
	assert_eq(_ship.story.flags.size(), 2)


func test_mission_progress_is_saved_when_it_is_over() -> void:
	_player.hold.add(KYRITE, 10.0)
	await wait_process_frames(1)
	_ship.ramp_duration = 0.25
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_physics_frames(ceili(_ship.ramp_duration * Engine.physics_ticks_per_second) + 2)
	assert_true(_mission.is_underway())
	await _move(_ship.to_global(Vector3(22.0, 0.0, 0.0)))
	_player.cargo.add(KYRITE, 100.0)
	_player.hold.add(OLVANE, 5.0)
	await wait_process_frames(1)
	assert_eq(_saved_hold(KYRITE), 10.0, "nothing saved mid-mission")
	await _move(_ship.to_global(Vector3(10.0, 2.5, 0.0)))
	assert_eq(_mission.state, Mission.State.RETURNED)
	assert_eq(_saved_hold(KYRITE), 110.0, "saved once everyone is back")
	assert_eq(_saved_hold(OLVANE), 5.0)


func test_quitting_mid_mission_loses_the_run() -> void:
	TEST_MAP.pick_mission(_map)
	_ship.ramp_button.use(_player)
	await wait_physics_frames(2)
	_player.hold.add(KYRITE, 50.0)
	await _restart()
	assert_false(_player.hold.items.has(KYRITE))


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


func test_ring_settings_are_saved() -> void:
	GameSettings.set_ring_size(0)
	GameSettings.set_ring_always_show(true)
	GameSettings.ring_size = GameSettings.RING_MEDIUM
	GameSettings.ring_always_show = false
	GameSettings.load_settings()
	assert_eq(GameSettings.ring_size, 0)
	assert_true(GameSettings.ring_always_show)
	assert_eq(GameSettings.ring_scale(), GameSettings.RING_SCALES[0])
	GameSettings.set_ring_size(GameSettings.RING_MEDIUM)
	GameSettings.set_ring_always_show(false)


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
	var hold: Dictionary = _saved(SaveGame.PLAYER_FILE)["hold"]
	var items: Dictionary = hold["items"]
	return items.get(_uid(ore_type), 0.0)


func _saved(file_name: String) -> Dictionary:
	var path: String = SaveGame.save_directory().path_join(file_name)
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _uid(resource: Resource) -> String:
	return ResourceUID.path_to_uid(resource.resource_path)


func _write(file_name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SaveGame.save_directory())
	var file := FileAccess.open(SaveGame.save_directory().path_join(file_name), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean() -> void:
	SaveGame.erase()
	if FileAccess.file_exists(GameSettings.path()):
		DirAccess.remove_absolute(GameSettings.path())
