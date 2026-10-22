extends GutTest
## What a save file holds and how older or damaged ones load (see `SaveGame`).

const TEST_MAP := preload("res://tests/support/test_map.gd")
const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")
const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const SUIT: Skill = preload("res://game/progression/skills/tree/reinforced_suit.tres")
const DASH: Skill = preload("res://game/progression/skills/tree/dash.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
const COBREL: AlloyType = preload("res://game/refinery/alloys/alloy_cobrel.tres")
const DIRECTORY: String = "user://test_save_format/"

var _map: Node3D
var _player: Player
var _ship: Ship


func test_unreadable_save_starts_fresh_and_is_kept() -> void:
	_write(SaveGame.PLAYER_FILE, "{ not json")
	await _restart()
	assert_push_error("can't read")
	assert_eq(_player.arsenal.weapons, [HARL, DRAY] as Array[WeaponType])
	var corrupt: String = SaveGame.save_directory().path_join(SaveGame.PLAYER_FILE + ".corrupt")
	assert_true(FileAccess.file_exists(corrupt))


func test_newer_save_is_not_read() -> void:
	_write(SaveGame.SHIP_FILE, JSON.stringify({"version": SaveGame.VERSION + 1, "hold": {}}))
	await _restart()
	assert_push_error("can't read")


func test_unknown_entries_are_skipped() -> void:
	var ship_data: Dictionary = {
		"version": SaveGame.VERSION,
		"story": ["quartermaster.ammo", 3, ""],
	}
	var player_data: Dictionary = {
		"version": SaveGame.VERSION,
		"hold":
		{
			KYRITE.resource_path: 30.0,
			"res://nothing.tres": 5.0,
			"user://ore.tres": 5.0,
			BRASK.resource_path: 5.0,
			OLVANE.resource_path: -4.0,
		},
		"found": [OLVANE.resource_path, BRASK.resource_path],
		"arsenal": [HARL.resource_path, "res://nothing.tres", 3, KYRITE.resource_path],
		"loadout": [DRAY.resource_path, BRASK.resource_path],
		"upgrades": {ARMOR.resource_path: 99, "res://nothing.tres": 2, DRILL.resource_path: "x"},
		"skills": {SUIT.resource_path: 99, ARMOR.resource_path: 1, DASH.resource_path: 0},
		"upgrade_jobs":
		{
			ARMOR.resource_path: {"level": 9, "started": 0.0, "seconds": 60.0},
			DRILL.resource_path: {"level": 2, "started": "x", "seconds": 60.0},
		},
		"skill_jobs":
		{
			DASH.resource_path: {"level": 1, "started": 1e12, "seconds": 60.0},
			SUIT.resource_path: {"level": 2, "started": 0.0, "seconds": 60.0},
		},
	}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	assert_eq(_player.hold.items.keys(), [KYRITE] as Array[ItemType])
	assert_eq(_player.hold.found.keys(), [KYRITE, OLVANE] as Array[ItemType])
	assert_eq(_ship.story.flags.keys(), [&"quartermaster.ammo"] as Array[StringName])
	assert_eq(_player.arsenal.weapons, [HARL] as Array[WeaponType])
	# Neither saved weapon is owned, and the loadout is never empty: the default's owned ones stay.
	assert_eq(_player.loadout.get_weapon(0), HARL)
	assert_null(_player.loadout.get_weapon(1), "the default Dray isn't owned")
	assert_eq(_player.upgrades.mk(ARMOR), ARMOR.max_mk(), "clamped")
	assert_eq(_player.upgrades.mk(DRILL), 1)
	assert_eq(_player.skills.rank(SUIT), SUIT.max_rank(), "clamped")
	assert_eq(_player.skills.ranks.size(), 1, "not a skill, rank 0")
	assert_true(_player.upgrades.jobs.is_empty(), "beyond the highest, a start that isn't a time")
	assert_eq(_player.skills.jobs.keys(), [DASH] as Array[Skill], "the rank after the current")


## Resources are saved by UID, so moving or renaming their files keeps the save working.
func test_resources_are_saved_by_uid() -> void:
	_player.hold.add(KYRITE, 10.0)
	_player.upgrades.raise(ARMOR)
	_player.skills.raise(DASH)
	await wait_process_frames(1)
	var ship_data: Dictionary = _saved(SaveGame.SHIP_FILE)
	var player_data: Dictionary = _saved(SaveGame.PLAYER_FILE)
	var hold: Dictionary = player_data["hold"]
	var found: Array = player_data["found"]
	var arsenal: Array = player_data["arsenal"]
	var loadout: Array = player_data["loadout"]
	var upgrades: Dictionary = player_data["upgrades"]
	var skills: Dictionary = player_data["skills"]
	assert_eq(hold, {_uid(KYRITE): 10.0})
	assert_eq(found, [_uid(KYRITE)])
	assert_eq(arsenal, [_uid(HARL), _uid(DRAY)])
	assert_eq(loadout, [_uid(HARL), _uid(DRAY)])
	assert_eq(upgrades, {_uid(ARMOR): 2.0})
	assert_eq(skills, {_uid(DASH): 1.0})
	assert_true(_uid(KYRITE).begins_with("uid://"))
	assert_false(ship_data.has("hold"), "the hold is the player's")


## The heat shield (level, project, what's paid) and where the ship is are the host's.
func test_heat_shield_and_position_are_saved() -> void:
	var mission := _map.get_node("Mission") as Mission
	_ship.heat_shield.install_next()
	_ship.heat_shield.set_project()
	_ship.heat_shield.take_from({MERIDINE: 120.0})
	var lisk: CelestialBody = mission.settings.system.body_by_id(&"lisk")
	mission.at_body = lisk
	_ship.heat_shield.emit_changed()
	await wait_process_frames(1)
	var saved: Dictionary = _saved(SaveGame.SHIP_FILE)
	var at: String = saved["at"]
	var shield: Dictionary = saved["shield"]
	var mk: float = shield["mk"]
	var project: bool = shield["project"]
	assert_eq(at, "lisk")
	assert_eq(mk, 2.0)
	assert_true(project)
	await _restart()
	mission = _map.get_node("Mission") as Mission
	assert_eq(_ship.heat_shield.mk, 2)
	assert_true(_ship.heat_shield.project)
	assert_eq(mission.at_body, lisk)
	var vehra: Region = mission.settings.system.body_by_id(&"vehra").regions[0]
	assert_not_null(mission.offer_for(vehra), "the planet it opened offers missions again")


func test_damaged_heat_shield_and_position_are_skipped() -> void:
	var ship_data: Dictionary = {
		"version": SaveGame.VERSION,
		"shield": {"mk": 99, "project": "yes", "paid": {KYRITE.resource_path: 5.0, "x": 3}},
		"at": "zairen",
	}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	await _restart()
	var mission := _map.get_node("Mission") as Mission
	assert_eq(_ship.heat_shield.mk, _ship.heat_shield.max_mk(), "clamped")
	assert_false(_ship.heat_shield.project)
	assert_eq(mission.at_body, mission.settings.system.body_by_id(&"zairen"))
	ship_data["shield"] = {"mk": 1}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	await _restart()
	mission = _map.get_node("Mission") as Mission
	assert_null(mission.at_body, "out of the shield's reach")


## Version 1 saved paths, from before the resources moved into game/ (and three ores were renamed).
func test_version_1_saves_still_load() -> void:
	var ship_data: Dictionary = {
		"version": 1,
		"hold":
		{
			"res://scenes/mining/ores/ore_cyan.tres": 30.0,
			"res://scenes/mining/ores/ore_pallin.tres": 12.0,
		},
		"found": ["res://scenes/mining/ores/ore_green.tres"],
	}
	var player_data: Dictionary = {
		"version": 1,
		"arsenal":
		[
			"res://scenes/weapons/types/blaster.tres",
			"res://scenes/weapons/types/hammer.tres",
			"res://scenes/weapons/types/shotgun.tres",
		],
		"loadout": ["res://scenes/weapons/types/shotgun.tres", null],
		"upgrades": {"res://scenes/upgrades/armor.tres": 3},
		"skills": {"res://scenes/skills/dash.tres": 1},
	}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	assert_eq(_player.hold.amount(KYRITE), 30.0, "renamed from cyan")
	assert_eq(_player.hold.amount(load("res://game/ores/types/ore_pallin.tres") as OreType), 12.0)
	assert_true(OLVANE in _player.hold.found, "renamed from green")
	assert_eq(_player.arsenal.weapons, [HARL, DRAY, BRASK] as Array[WeaponType])
	assert_eq(_player.loadout.get_weapon(0), BRASK)
	assert_null(_player.loadout.get_weapon(1))
	assert_eq(_player.upgrades.mk(ARMOR), 3)
	assert_eq(_player.skills.rank(DASH), 1)
	await wait_process_frames(1)
	var saved: Dictionary = _saved(SaveGame.PLAYER_FILE)
	var hold: Dictionary = saved["hold"]
	var version: float = saved["version"]
	assert_eq(version, float(SaveGame.VERSION), "written again in the current format")
	assert_has(hold, _uid(KYRITE))


## Up to version 2 the hold was the ship's: it moves into the player's save, nothing lost.
func test_version_2_hold_moves_to_the_player() -> void:
	var ship_data: Dictionary = {
		"version": 2,
		"hold": {_uid(KYRITE): 40.0, _uid(MERIDINE): 0.0},
		"found": [_uid(KYRITE), _uid(MERIDINE), _uid(OLVANE)],
		"story": ["quartermaster.ammo"],
	}
	var player_data: Dictionary = {"version": 2, "arsenal": [_uid(HARL)]}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	assert_eq(_player.hold.amount(KYRITE), 40.0)
	assert_true(_player.hold.has_found(MERIDINE), "found, though spent")
	assert_true(_player.hold.has_found(OLVANE))
	assert_true(_ship.story.is_set(&"quartermaster.ammo"))
	await wait_process_frames(1)
	var ship_saved: Dictionary = _saved(SaveGame.SHIP_FILE)
	var player_saved: Dictionary = _saved(SaveGame.PLAYER_FILE)
	var hold: Dictionary = player_saved["hold"]
	var version: float = ship_saved["version"]
	assert_eq(version, float(SaveGame.VERSION), "written again in the current format")
	assert_false(ship_saved.has("hold"), "gone from the ship's save")
	assert_false(ship_saved.has("found"))
	var kyrite: float = hold[_uid(KYRITE)]
	assert_eq(kyrite, 40.0)
	await _restart()
	assert_eq(_player.hold.amount(KYRITE), 40.0, "not doubled on the next load")


## Up to version 3 the miner upgrades were the player's: they move onto M-01.
func test_version_3_miner_levels_move_onto_m01() -> void:
	var tank: Upgrade = load("res://game/progression/upgrades/miner_tank.tres")
	var player_data: Dictionary = {
		"version": 3,
		"arsenal": [_uid(HARL)],
		"upgrades": {_uid(ARMOR): 2, _uid(DRILL): 3},
		"upgrade_jobs": {_uid(tank): {"level": 2, "started": 1e12, "seconds": 60.0}},
	}
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	var first: CraftedMiner = _player.fleet.get_miner(1)
	assert_eq(first.upgrades.mk(DRILL), 3)
	assert_true(first.upgrades.is_running(tank), "with its level under way")
	assert_eq(_player.upgrades.mk(DRILL), 1, "no longer the player's")
	assert_false(_player.upgrades.is_running(tank))
	assert_eq(_player.upgrades.mk(ARMOR), 2, "the armor stays")
	await wait_process_frames(1)
	var saved: Dictionary = _saved(SaveGame.PLAYER_FILE)
	assert_false((saved["upgrades"] as Dictionary).has(_uid(DRILL)))
	await _restart()
	assert_eq(_player.fleet.get_miner(1).upgrades.mk(DRILL), 3, "kept on the next load")


func test_crafted_miners_are_saved() -> void:
	_player.fleet.build_all()
	_player.fleet.get_miner(2).going_along = false
	_player.fleet.get_miner(4).upgrades.raise(DRILL)
	_player.fleet.get_miner(5).upgrades.start(DRILL, 1e12)
	_player.fleet.get_miner(3).out = true
	_player.fleet.get_miner(6).out = true
	_player.fleet.end_run("Torvane, Redscar Flats")
	_player.fleet.start_build(3, 1e12, 180.0)
	await wait_process_frames(1)
	await _restart()
	var fleet: MinerFleet = _player.fleet
	assert_false(fleet.get_miner(2).going_along)
	assert_eq(fleet.get_miner(4).upgrades.mk(DRILL), 2)
	assert_true(fleet.get_miner(5).upgrades.is_running(DRILL))
	assert_false(fleet.get_miner(3).is_built())
	assert_almost_eq(fleet.get_miner(3).build.started, 1e12, 0.001)
	assert_true(fleet.is_empty(6))
	assert_eq(fleet.lost_at[6], "Torvane, Redscar Flats")


func test_a_lost_m01_stays_lost() -> void:
	_player.fleet.take(_player.fleet.get_miner(1))
	_player.fleet.end_run("there")
	await wait_process_frames(1)
	await _restart()
	assert_true(_player.fleet.is_empty(1))
	assert_eq(_player.fleet.lost_at[1], "there")


func test_damaged_miners_are_skipped() -> void:
	var player_data: Dictionary = {
		"version": SaveGame.VERSION,
		"arsenal": [_uid(HARL)],
		"miners":
		[
			{"number": 1, "upgrades": {_uid(DRILL): 2, _uid(ARMOR): 3}},
			{"number": 1},
			{"number": 9},
			"x",
			{"number": 2, "build": {"level": 1, "started": "x", "seconds": 60.0}},
			{"number": 3, "upgrade_jobs": {_uid(DRILL): {"level": 5, "started": 0, "seconds": 1}}},
		],
		"lost_miners": {"1": "here", "4": "there", "x": "nowhere", "5": 3},
	}
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	var fleet: MinerFleet = _player.fleet
	assert_eq(fleet.miners.keys(), [1, 3] as Array[int])
	assert_eq(fleet.get_miner(1).upgrades.mk(DRILL), 2)
	assert_eq(fleet.get_miner(1).upgrades.levels.size(), 1, "not a miner's part")
	assert_true(fleet.get_miner(3).upgrades.jobs.is_empty(), "not the next level")
	assert_eq(fleet.lost_at.keys(), [4] as Array[int])


## Every place a version 1 path moved to is there.
func test_moved_paths_exist() -> void:
	for old: String in SaveGame.MOVED:
		var moved: String = SaveGame.MOVED[old]
		if moved.ends_with("/"):
			assert_true(DirAccess.dir_exists_absolute(moved), moved)
		else:
			assert_true(ResourceLoader.exists(moved), moved)


## Weapons are never taken away and the loadout is never empty, so a save without a known weapon
## is damaged: the player keeps the default weapons instead of going out unarmed.
func test_save_without_a_known_weapon_keeps_the_defaults() -> void:
	var player_data: Dictionary = {
		"version": SaveGame.VERSION,
		"arsenal": ["res://nothing.tres"],
		"loadout": [null, null],
	}
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	assert_eq(_player.arsenal.weapons, [HARL, DRAY] as Array[WeaponType])
	assert_eq(_player.loadout.get_weapon(0), HARL)
	assert_eq(_player.loadout.get_weapon(1), DRAY)
	assert_eq(_player.get_weapon_type(), HARL)


func test_furnaces_and_batches_are_saved() -> void:
	_ship.furnaces.unlock()
	_ship.furnaces.unlock()
	_player.hold.add(KYRITE, 100.0)
	_player.hold.add(VYREL, 100.0)
	var now: float = Time.get_unix_time_from_system()
	assert_true(_player.refining.start(1, COBREL, 4, _player.hold, now))
	await wait_process_frames(1)
	var furnaces: float = _saved(SaveGame.SHIP_FILE)["furnaces"]
	assert_eq(furnaces, 2.0)
	var batches: Array = _saved(SaveGame.PLAYER_FILE)["refining"]
	assert_eq(batches.size(), 1)
	var batch: Dictionary = batches[0]
	var slot: float = batch["slot"]
	var alloy: String = batch["alloy"]
	var bars: float = batch["bars"]
	var done: float = batch["done"]
	var started: float = batch["started"]
	assert_eq(slot, 1.0)
	assert_eq(alloy, _uid(COBREL))
	assert_eq(bars, 4.0)
	assert_eq(done, 0.0)
	assert_almost_eq(started, now, 0.001)
	await _restart()
	assert_eq(_ship.furnaces.unlocked, 2)
	var loaded: AlloyBatch = _player.refining.get_batch(1)
	assert_eq(loaded.alloy, COBREL)
	assert_eq(loaded.bars, 4)
	assert_almost_eq(loaded.started, now, 0.001)
	assert_eq(_player.hold.amount(KYRITE), 60.0, "paid once")


func test_bars_finished_while_away_are_in_the_hold_on_loading() -> void:
	var started: float = Time.get_unix_time_from_system() - COBREL.seconds_per_bar * 2.5
	var player_data: Dictionary = {
		"version": SaveGame.VERSION,
		"refining":
		[
			{"slot": 0, "alloy": _uid(COBREL), "bars": 5, "done": 1, "started": started},
		],
	}
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	assert_eq(_player.hold.amount(COBREL), 1.0, "the second bar; the first was in the hold already")
	assert_eq(_player.refining.get_batch(0).done, 2)


func test_damaged_batches_are_skipped() -> void:
	_write(SaveGame.SHIP_FILE, JSON.stringify({"version": SaveGame.VERSION, "furnaces": 9}))
	var now: float = Time.get_unix_time_from_system()
	var player_data: Dictionary = {
		"version": SaveGame.VERSION,
		"refining":
		[
			{"slot": 0, "alloy": _uid(KYRITE), "bars": 5, "done": 0, "started": now},
			{"slot": 7, "alloy": _uid(COBREL), "bars": 5, "done": 0, "started": now},
			{"slot": 1, "alloy": _uid(COBREL), "bars": 5, "done": 5, "started": now},
			{"slot": 2, "alloy": _uid(COBREL), "bars": 5, "done": 0},
			"x",
			{"slot": 3, "alloy": _uid(COBREL), "bars": 5, "done": 0, "started": now},
		],
	}
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	assert_eq(_ship.furnaces.unlocked, Refining.SLOTS, "clamped")
	for slot: int in 3:
		assert_null(_player.refining.get_batch(slot), "slot %d" % slot)
	assert_not_null(_player.refining.get_batch(3))


func before_each() -> void:
	SaveGame.directory = DIRECTORY
	_clean()
	await _start()


func after_each() -> void:
	_clean()
	SaveGame.directory = ""


func _start() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func _restart() -> void:
	_map.free()
	await _start()


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
