extends "res://tests/support/save_test.gd"
## How older, newer or damaged save files load, and that resources are saved by UID (see
## `SaveGame`; what the saves hold: `test_save_contents.gd`).

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


## A section holding the wrong kind of value is skipped like an unknown entry.
func test_sections_of_the_wrong_kind_are_skipped() -> void:
	var ship_data: Dictionary = {"version": SaveGame.VERSION, "story": "x", "shield": [1]}
	var player_data: Dictionary = {
		"version": SaveGame.VERSION,
		"hold": [KYRITE.resource_path],
		"arsenal": {HARL.resource_path: 1},
		"upgrades": [ARMOR.resource_path],
		"skills": "x",
		"upgrade_jobs": [],
		"skill_jobs": 3,
		"miners": {},
	}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	assert_true(_player.hold.items.is_empty())
	assert_eq(_player.arsenal.weapons, [HARL, DRAY] as Array[WeaponType])
	assert_eq(_player.upgrades.mk(ARMOR), 1)
	assert_true(_player.skills.ranks.is_empty())
	assert_true(_ship.story.flags.is_empty())


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
