extends "res://tests/support/save_test.gd"
## How save files of another version or damaged ones load, and that resources are saved by UID
## (see `SaveGame`; what the saves hold: `test_save_contents.gd`).

const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const BRASK: WeaponType = preload("res://game/weapons/types/brask/brask.tres")
const DRAY: WeaponType = preload("res://game/weapons/types/dray/dray.tres")
const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const SUIT: Skill = preload("res://game/progression/skills/tree/reinforced_suit.tres")
const DASH: Skill = preload("res://game/progression/skills/tree/dash.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const OLVANE: OreType = preload("res://game/ores/types/ore_olvane.tres")


func test_unreadable_save_starts_fresh_and_is_kept() -> void:
	_write(SaveGame.PLAYER_FILE, "{ not json")
	await _restart()
	assert_push_error("can't read")
	assert_eq(_player.arsenal.weapons, [HARL, DRAY] as Array[WeaponType])
	var corrupt: String = SaveGame.save_directory().path_join(SaveGame.PLAYER_FILE + ".corrupt")
	assert_true(FileAccess.file_exists(corrupt))


## Older saves aren't converted before the release: they start over like newer ones.
func test_save_of_another_version_is_not_read() -> void:
	for version: int in [SaveGame.VERSION - 1, SaveGame.VERSION + 1]:
		_write(SaveGame.SHIP_FILE, JSON.stringify({"version": version, "cradles": 4}))
		await _restart()
		assert_push_error("can't read")
		assert_eq(_ship.cradles.open, Cradles.START, "version %d" % version)


func test_unknown_entries_are_skipped() -> void:
	var ship_data: Dictionary = {
		"version": SaveGame.VERSION,
		"story": ["quartermaster.ammo", 3, "", "Not A Flag"],
	}
	var player_data: Dictionary = {
		"version": SaveGame.VERSION,
		"hold":
		{
			"items":
			{
				_uid(KYRITE): 30.0,
				"uid://nothing": 5.0,
				KYRITE.resource_path: 5.0,
				_uid(BRASK): 5.0,
				_uid(OLVANE): -4.0,
			},
			"found": [_uid(OLVANE), _uid(BRASK)],
		},
		"arsenal": {"weapons": [_uid(HARL), "uid://nothing", 3, _uid(KYRITE)], "blueprints": []},
		"loadout": [_uid(DRAY), _uid(BRASK)],
		"upgrades":
		{
			"levels": {_uid(ARMOR): 99, "uid://nothing": 2, _uid(DRILL): "x"},
			"jobs":
			{
				_uid(ARMOR): {"level": 9, "started": 0.0, "seconds": 60.0},
				_uid(DRILL): {"level": 2, "started": "x", "seconds": 60.0},
			},
		},
		"skills":
		{
			"ranks": {_uid(SUIT): 99, _uid(ARMOR): 1, _uid(DASH): 0},
			"jobs":
			{
				_uid(DASH): {"level": 1, "started": 1e12, "seconds": 60.0},
				_uid(SUIT): {"level": 2, "started": 0.0, "seconds": 60.0},
			},
		},
	}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	assert_eq(_player.hold.items.keys(), [KYRITE] as Array[ItemType], "by UID only")
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
	await wait_process_frames(1)
	var story: Array = _saved(SaveGame.SHIP_FILE)["story"]
	assert_eq(story, ["quartermaster.ammo"], "the repaired save written again")


## A section holding the wrong kind of value is skipped like an unknown entry.
func test_sections_of_the_wrong_kind_are_skipped() -> void:
	var ship_data: Dictionary = {
		"version": SaveGame.VERSION,
		"story": "x",
		"shield": [1],
		"reactions": 3,
		"quests": [],
		"director": "x",
		"at": 7,
	}
	var player_data: Dictionary = {
		"version": SaveGame.VERSION,
		"hold": [_uid(KYRITE)],
		"refining": {},
		"arsenal": [_uid(HARL)],
		"loadout": {},
		"upgrades": {"levels": [_uid(ARMOR)]},
		"skills": "x",
		"fleet": {"miners": {}},
		"hints": 3,
		"finished": {"item": 1},
	}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	assert_true(_player.hold.items.is_empty())
	assert_eq(_player.arsenal.weapons, [HARL, DRAY] as Array[WeaponType])
	assert_eq(_player.upgrades.mk(ARMOR), 1)
	assert_true(_player.skills.ranks.is_empty())
	assert_true(_ship.story.flags.is_empty())
	assert_true(_ship.quests.accepted.is_empty())
	assert_eq(_ship.director.runs, 0)
	assert_true(_player.finished_jobs.entries.is_empty())
	assert_false(_player.fleet.is_empty(1), "M-01 stays")


## Resources are saved by UID, so moving or renaming their files keeps the save working.
func test_resources_are_saved_by_uid() -> void:
	_player.hold.add(KYRITE, 10.0)
	_player.upgrades.raise(ARMOR)
	_player.skills.raise(DASH)
	await wait_process_frames(1)
	var ship_data: Dictionary = _saved(SaveGame.SHIP_FILE)
	var player_data: Dictionary = _saved(SaveGame.PLAYER_FILE)
	var hold: Dictionary = player_data["hold"]
	var arsenal: Dictionary = player_data["arsenal"]
	var loadout: Array = player_data["loadout"]
	var upgrades: Dictionary = player_data["upgrades"]
	var skills: Dictionary = player_data["skills"]
	var items: Dictionary = hold["items"]
	var found: Array = hold["found"]
	var weapons: Array = arsenal["weapons"]
	var levels: Dictionary = upgrades["levels"]
	var ranks: Dictionary = skills["ranks"]
	assert_eq(items, {_uid(KYRITE): 10.0})
	assert_eq(found, [_uid(KYRITE)])
	assert_eq(weapons, [_uid(HARL), _uid(DRAY)])
	assert_eq(loadout, [_uid(HARL), _uid(DRAY)])
	assert_eq(levels, {_uid(ARMOR): 2.0})
	assert_eq(ranks, {_uid(DASH): 1.0})
	assert_true(_uid(KYRITE).begins_with("uid://"))
	assert_false(ship_data.has("hold"), "the hold is the player's")


## Weapons are never taken away and the loadout is never empty, so a save without a known weapon
## is damaged: the player keeps the default weapons instead of going out unarmed.
func test_save_without_a_known_weapon_keeps_the_defaults() -> void:
	var player_data: Dictionary = {
		"version": SaveGame.VERSION,
		"arsenal": {"weapons": ["uid://nothing"]},
		"loadout": [null, null],
	}
	_write(SaveGame.PLAYER_FILE, JSON.stringify(player_data))
	await _restart()
	assert_eq(_player.arsenal.weapons, [HARL, DRAY] as Array[WeaponType])
	assert_eq(_player.loadout.get_weapon(0), HARL)
	assert_eq(_player.loadout.get_weapon(1), DRAY)
	assert_eq(_player.arms.get_weapon_type(), HARL)
