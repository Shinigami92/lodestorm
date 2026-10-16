extends GutTest
## What a save file holds and how older or damaged ones load (see `SaveGame`).

const TEST_MAP := preload("res://tests/support/test_map.gd")
const BLASTER: WeaponType = preload("res://game/weapons/types/blaster.tres")
const SHOTGUN: WeaponType = preload("res://game/weapons/types/shotgun.tres")
const HAMMER: WeaponType = preload("res://game/weapons/types/hammer.tres")
const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const SUIT: Skill = preload("res://game/progression/skills/tree/reinforced_suit.tres")
const DASH: Skill = preload("res://game/progression/skills/tree/dash.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")
const DIRECTORY: String = "user://test_save_format/"

var _map: Node3D
var _player: Player
var _ship: Ship


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
			KYRITE.resource_path: 30.0,
			"res://nothing.tres": 5.0,
			"user://ore.tres": 5.0,
			SHOTGUN.resource_path: 5.0,
			OLVANE.resource_path: -4.0,
		},
		"story": ["quartermaster.ammo", 3, ""],
	}
	var player_data: Dictionary = {
		"version": SaveGame.VERSION,
		"arsenal": [BLASTER.resource_path, "res://nothing.tres", 3, KYRITE.resource_path],
		"loadout": [HAMMER.resource_path, SHOTGUN.resource_path],
		"upgrades": {ARMOR.resource_path: 99, "res://nothing.tres": 2, DRILL.resource_path: "x"},
		"skills": {SUIT.resource_path: 99, ARMOR.resource_path: 1, DASH.resource_path: 0},
	}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	assert_eq(_ship.hold.keys(), [KYRITE] as Array[OreType])
	assert_eq(_ship.story.flags.keys(), [&"quartermaster.ammo"] as Array[StringName])
	assert_eq(_player.arsenal.weapons, [BLASTER] as Array[WeaponType])
	# Neither saved weapon is owned, and the loadout is never empty: the default's owned ones stay.
	assert_eq(_player.loadout.get_weapon(0), BLASTER)
	assert_null(_player.loadout.get_weapon(1), "the default hammer isn't owned")
	assert_eq(_player.upgrades.mk(ARMOR), ARMOR.max_mk(), "clamped")
	assert_eq(_player.upgrades.mk(DRILL), 1)
	assert_eq(_player.skills.rank(SUIT), SUIT.max_rank(), "clamped")
	assert_eq(_player.skills.ranks.size(), 1, "not a skill, rank 0")


## Resources are saved by UID, so moving or renaming their files keeps the save working.
func test_resources_are_saved_by_uid() -> void:
	_ship.add_to_hold(KYRITE, 10.0)
	_player.upgrades.raise(ARMOR)
	_player.skills.raise(DASH)
	await wait_process_frames(1)
	var ship_data: Dictionary = _saved(SaveGame.SHIP_FILE)
	var player_data: Dictionary = _saved(SaveGame.PLAYER_FILE)
	var hold: Dictionary = ship_data["hold"]
	var found: Array = ship_data["found"]
	var arsenal: Array = player_data["arsenal"]
	var loadout: Array = player_data["loadout"]
	var upgrades: Dictionary = player_data["upgrades"]
	var skills: Dictionary = player_data["skills"]
	assert_eq(hold, {_uid(KYRITE): 10.0})
	assert_eq(found, [_uid(KYRITE)])
	assert_eq(arsenal, [_uid(BLASTER), _uid(HAMMER)])
	assert_eq(loadout, [_uid(BLASTER), _uid(HAMMER)])
	assert_eq(upgrades, {_uid(ARMOR): 2.0})
	assert_eq(skills, {_uid(DASH): 1.0})
	assert_true(_uid(KYRITE).begins_with("uid://"))


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
	assert_eq(_ship.hold[KYRITE], 30.0, "renamed from cyan")
	assert_eq(_ship.hold[load("res://game/ores/types/ore_pallin.tres") as OreType], 12.0)
	assert_true(OLVANE in _ship.found_ores, "renamed from green")
	assert_eq(_player.arsenal.weapons, [BLASTER, HAMMER, SHOTGUN] as Array[WeaponType])
	assert_eq(_player.loadout.get_weapon(0), SHOTGUN)
	assert_null(_player.loadout.get_weapon(1))
	assert_eq(_player.upgrades.mk(ARMOR), 3)
	assert_eq(_player.skills.rank(DASH), 1)
	await wait_process_frames(1)
	var saved: Dictionary = _saved(SaveGame.SHIP_FILE)
	var hold: Dictionary = saved["hold"]
	var version: float = saved["version"]
	assert_eq(version, float(SaveGame.VERSION), "written again in the current format")
	assert_has(hold, _uid(KYRITE))


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
	assert_eq(_player.arsenal.weapons, [BLASTER, HAMMER] as Array[WeaponType])
	assert_eq(_player.loadout.get_weapon(0), BLASTER)
	assert_eq(_player.loadout.get_weapon(1), HAMMER)
	assert_eq(_player.get_weapon_type(), BLASTER)


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
