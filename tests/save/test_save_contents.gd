extends "res://tests/support/save_test.gd"
## What the saves hold besides the gear: the heat shield and where the ship is, the miners and the
## cradles open, the furnaces and their batches, each also from a damaged save (see `SaveGame`).

const HARL: WeaponType = preload("res://game/weapons/types/harl/harl.tres")
const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")
const DRILL: Upgrade = preload("res://game/progression/upgrades/miner_drill.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const MERIDINE: OreType = preload("res://game/ores/types/ore_meridine.tres")
const VYREL: OreType = preload("res://game/ores/types/ore_vyrel.tres")
const COBREL: AlloyType = preload("res://game/refinery/alloys/alloy_cobrel.tres")


## The heat shield (level, project, what's paid) and where the ship is are the host's.
func test_heat_shield_and_position_are_saved() -> void:
	var voyage := _map.get_node("Voyage") as Voyage
	_ship.heat_shield.install_next()
	_ship.heat_shield.set_project()
	_ship.heat_shield.take_from({MERIDINE: 120.0})
	var lisk: CelestialBody = voyage.settings.system.body_by_id(&"lisk")
	voyage.at_body = lisk
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
	voyage = _map.get_node("Voyage") as Voyage
	assert_eq(_ship.heat_shield.mk, 2)
	assert_true(_ship.heat_shield.project)
	assert_eq(voyage.at_body, lisk)
	var vehra: Region = voyage.settings.system.body_by_id(&"vehra").regions[0]
	assert_not_null(voyage.offer_for(vehra), "the planet it opened offers missions again")


func test_damaged_heat_shield_and_position_are_skipped() -> void:
	var ship_data: Dictionary = {
		"version": SaveGame.VERSION,
		"shield": {"mk": 99, "project": "yes", "paid": {KYRITE.resource_path: 5.0, "x": 3}},
		"at": "zairen",
	}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	await _restart()
	var voyage := _map.get_node("Voyage") as Voyage
	assert_eq(_ship.heat_shield.mk, _ship.heat_shield.max_mk(), "clamped")
	assert_false(_ship.heat_shield.project)
	assert_eq(voyage.at_body, voyage.settings.system.body_by_id(&"zairen"))
	ship_data["shield"] = {"mk": 1}
	_write(SaveGame.SHIP_FILE, JSON.stringify(ship_data))
	await _restart()
	voyage = _map.get_node("Voyage") as Voyage
	assert_null(voyage.at_body, "out of the shield's reach")


func test_crafted_miners_are_saved() -> void:
	_player.fleet.cradles.restore(MinerFleet.SLOTS)
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
	assert_eq(fleet.per_run(), MinerFleet.SLOTS, "the ship's cradles open")


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


func test_open_cradles_are_saved() -> void:
	assert_eq(_ship.cradles.open, Cradles.START)
	_ship.cradles.open_next()
	await wait_process_frames(1)
	var open: float = _saved(SaveGame.SHIP_FILE)["cradles"]
	assert_eq(open, 3.0)
	await _restart()
	assert_eq(_ship.cradles.open, 3)
	assert_eq(_player.fleet.cradles, _ship.cradles, "the player counts the ship's")


func test_damaged_cradles_are_skipped() -> void:
	_write(SaveGame.SHIP_FILE, JSON.stringify({"version": SaveGame.VERSION, "cradles": "x"}))
	await _restart()
	assert_eq(_ship.cradles.open, Cradles.START)


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
