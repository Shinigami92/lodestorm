class_name StatsRecorder
extends Node
## Keeps the statistics of the local `player` from the `GameEvents` bus: counters over all
## sessions (`totals`, in `stats/totals.json`) and over the current run (`run`), and a log of this
## session (`stats/sessions/<date>_<time>.jsonl`: one JSON object per line, what happened when),
## both in `stats/` under `SaveGame.directory` (nothing is written while it's empty: the tests).
## Frequent events (attacks, hits, damage dealt, healing, ore arriving) are only counted; the log
## gets each run's counters when it ends (`mission_ended`). The player's damage taken is logged
## once per cause and second. It also counts the seconds and meters the player spends aboard,
## outside, in menus and dead. Nothing waits for the disk: the log is written through a buffer
## flushed every few seconds, the totals every half minute, when a run ends and when the game
## quits. Resetting the progress keeps the statistics. See docs/technical/saving.md (Statistics).

## The format of `totals.json`; raise it (and convert older files) when it changes.
const VERSION: int = 1
const FOLDER: String = "stats"
const TOTALS_FILE: String = "totals.json"
const SESSIONS_FOLDER: String = "sessions"
## Session logs kept, the newest; older ones are deleted when a session starts.
const KEEP_SESSIONS: int = 20
## Seconds between writes of the log's buffer, and of the totals (when they changed).
const FLUSH_INTERVAL: float = 5.0
const SAVE_INTERVAL: float = 30.0
## Damage taken from one cause within this many seconds is logged as one line.
const HURT_MERGE: float = 1.0
## A move longer than this within one physics frame is a teleport (a respawn), not walked (m).
const TELEPORT_DISTANCE: float = 3.0

## The player whose statistics these are (the local one; the first local player without one).
@export var player: Player
@export var ship: Ship
@export var mission: Mission
@export var voyage: Voyage

## Counters over all sessions, and over the run underway (or the last one).
var totals := StatCounters.new()
var run := StatCounters.new()
## Runs started this session.
var runs: int = 0

## The open session log, or null while nothing is written.
var _log: FileAccess
## Seconds since the session started, and since the run started (while one is underway).
var _time: float = 0.0
var _run_time: float = -1.0
var _since_flush: float = 0.0
var _since_save: float = 0.0
var _dirty: bool = false
## Damage taken not logged yet, per cause: {amount, hits, t}.
var _hurts: Dictionary[String, Dictionary] = {}
var _last_position := Vector3.INF
## Ids of resources and scenes, looked up once (`GameEvents.id_of`).
var _ids: Dictionary[Object, String] = {}


## The folder of the statistics (empty while nothing is written).
static func stats_directory() -> String:
	return SaveGame.directory.path_join(FOLDER) if SaveGame.directory else ""


func _ready() -> void:
	if not player:
		player = Player.first_local(get_tree())
	_load_totals()
	_open_log()
	totals.add("sessions")
	_write_line(
		"session_started",
		{
			"date": Time.get_datetime_string_from_system(),
			"game": ProjectSettings.get_setting("application/config/version", ""),
			"engine": Engine.get_version_info()["string"],
			"os": OS.get_name(),
			"editor": OS.has_feature("editor"),
			"language": TranslationServer.get_locale(),
		}
	)
	_connect_events()


func _exit_tree() -> void:
	_end_session()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_end_session()


func _physics_process(delta: float) -> void:
	_time += delta
	if _run_time >= 0.0:
		_run_time += delta
	_count_time(delta)
	_log_hurts(false)
	_since_flush += delta
	if _since_flush >= FLUSH_INTERVAL:
		_since_flush = 0.0
		flush_log()
	_since_save += delta
	if _since_save >= SAVE_INTERVAL:
		_since_save = 0.0
		if _dirty:
			save_totals()


## Writes the totals (nothing happens while nothing is written).
func save_totals() -> void:
	_dirty = false
	var directory: String = stats_directory()
	if not directory:
		return
	var path: String = directory.path_join(TOTALS_FILE)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file:
		push_error("Stats: can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	var data: Dictionary = {
		"version": VERSION,
		"updated": Time.get_datetime_string_from_system(),
		"counters": totals.to_data(),
	}
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)


## Writes what the session log holds back (the tests read it right away).
func flush_log() -> void:
	if _log:
		_log.flush()


## Adds `amount` to counter `counter` at `labels`, over all sessions and in the run.
func count(counter: String, labels: Array[String] = [], amount: float = 1.0) -> void:
	totals.add(counter, labels, amount)
	run.add(counter, labels, amount)
	_dirty = true


## The id of `of` for the counters and the log: a resource's (`GameEvents.id_of`), a node's scene
## (or its owner's) without `res://game/` and the extension, "none" for null.
func id_of(of: Object) -> String:
	if not is_instance_valid(of):
		return "none"
	if of in _ids:
		return _ids[of]
	var id: String = "none"
	if of is Resource:
		id = GameEvents.id_of(of as Resource)
	elif of is Node:
		var node := of as Node
		while node and node.scene_file_path.is_empty():
			node = node.owner
		if node:
			id = node.scene_file_path.trim_prefix("res://game/").trim_suffix(".tscn")
	_ids[of] = id
	return id


## What dealt damage to the player, as a label: an alien's strain, "storm", a hazard's or acid's
## kind (its class, e.g. `acid_puddle`), "unknown" without one.
func cause_of(cause: Node) -> String:
	if not is_instance_valid(cause):
		return "unknown"
	if cause is Alien:
		return id_of((cause as Alien).strain)
	if cause is Mission:
		return "storm"
	var script := cause.get_script() as Script
	if script and script.get_global_name():
		return String(script.get_global_name()).to_snake_case()
	return String(cause.name).to_snake_case()


func _connect_events() -> void:
	var events: GameEvents = GameEvents.bus
	events.weapon_attacked.connect(_on_weapon_attacked)
	events.alien_hit.connect(_on_alien_hit)
	events.alien_damaged.connect(_on_alien_damaged)
	events.alien_killed.connect(_on_alien_killed)
	events.alien_appeared.connect(_on_alien_appeared)
	events.nest_damaged.connect(_on_nest_damaged)
	events.nest_destroyed.connect(_on_nest_destroyed)
	events.reload_started.connect(_on_reload_started)
	events.reload_timed.connect(_on_reload_timed)
	events.reload_denied.connect(_on_reload_denied)
	events.ammo_paid.connect(_on_ammo_paid)
	events.shield_blocked.connect(_on_shield_blocked)
	events.dashed.connect(_on_dashed)
	events.player_hurt.connect(_on_player_hurt)
	events.player_died.connect(_on_player_died)
	events.player_healed.connect(_on_player_healed)
	events.player_respawned.connect(_on_player_respawned)
	events.miner_placed.connect(_on_miner_handled.bind("miners_placed", "miner_placed"))
	events.miner_picked_up.connect(_on_miner_handled.bind("miners_picked_up", "miner_picked_up"))
	events.miner_broke.connect(_on_miner_changed.bind("miners_broken", "miner_broke"))
	events.miner_repaired.connect(_on_miner_changed.bind("miners_repaired", "miner_repaired"))
	events.miner_ran_dry.connect(_on_miner_changed.bind("miners_ran_dry", "miner_ran_dry"))
	events.ore_collected.connect(_on_ore.bind("ore_collected", ""))
	events.ore_hauled.connect(_on_ore.bind("ore_hauled", "ore_hauled"))
	events.ore_lost.connect(_on_ore.bind("ore_lost", "ore_lost"))
	events.weapon_unlocked.connect(_on_weapon_gained.bind("weapons_unlocked", "weapon_unlocked"))
	events.blueprint_learned.connect(
		_on_weapon_gained.bind("blueprints_learned", "blueprint_learned")
	)
	events.upgrade_finished.connect(_on_upgrade_finished)
	events.skill_finished.connect(_on_skill_finished)
	events.bars_refined.connect(_on_bars_refined)
	events.heat_shield_raised.connect(_on_heat_shield_raised)
	events.story_flag_set.connect(_on_story_flag_set)
	events.mission_started.connect(_on_mission_started)
	events.storm_started.connect(_on_storm_started)
	events.mission_ended.connect(_on_mission_ended)
	events.menu_opened.connect(_on_menu_opened)


## Whether `of` is the player whose statistics these are.
func _is_mine(of: Player) -> bool:
	return of != null and of == player


func _on_weapon_attacked(by: Player, weapon_type: WeaponType) -> void:
	if _is_mine(by):
		count("attacks", [id_of(weapon_type)])


func _on_alien_hit(by: Player, weapon_type: WeaponType, alien: Alien, armored: bool) -> void:
	if not _is_mine(by):
		return
	var labels: Array[String] = [id_of(weapon_type), id_of(alien.strain)]
	count("hits", labels)
	if armored:
		count("hits_armored", labels)


func _on_alien_damaged(by: Player, weapon_type: WeaponType, alien: Alien, amount: float) -> void:
	if _is_mine(by):
		count("damage_dealt", [id_of(weapon_type), id_of(alien.strain)], amount)


func _on_alien_killed(by: Player, weapon_type: WeaponType, alien: Alien) -> void:
	if not _is_mine(by):
		return
	count("kills", [id_of(weapon_type), id_of(alien.strain)])
	_write_line(
		"alien_killed",
		{
			"weapon": id_of(weapon_type),
			"strain": id_of(alien.strain),
			"role": str(Alien.Role.keys()[alien.role]).to_lower(),
		}
	)


func _on_alien_appeared(alien: Alien) -> void:
	count("aliens_appeared", [id_of(alien.strain)])


func _on_nest_damaged(by: Player, weapon_type: WeaponType, _nest: AlienNest, amount: float) -> void:
	if _is_mine(by):
		count("damage_dealt_nests", [id_of(weapon_type)], amount)


func _on_nest_destroyed(by: Player, weapon_type: WeaponType, _nest: AlienNest) -> void:
	count("nests_destroyed", [id_of(weapon_type) if _is_mine(by) else "others"])
	_write_line("nest_destroyed", {"weapon": id_of(weapon_type), "mine": _is_mine(by)})


func _on_reload_started(by: Player, weapon_type: WeaponType, vent: bool) -> void:
	if not _is_mine(by):
		return
	var kind: String = "vent" if vent else "reload"
	count("reloads", [id_of(weapon_type), kind])
	_write_line("reload_started", {"weapon": id_of(weapon_type), "kind": kind})


func _on_reload_timed(by: Player, weapon_type: WeaponType, hit: bool) -> void:
	if not _is_mine(by):
		return
	var result: String = "hit" if hit else "miss"
	count("reload_presses", [id_of(weapon_type), result])
	_write_line("reload_timed", {"weapon": id_of(weapon_type), "result": result})


func _on_reload_denied(by: Player, weapon_type: WeaponType) -> void:
	if _is_mine(by):
		count("reloads_denied", [id_of(weapon_type)])
		_write_line("reload_denied", {"weapon": id_of(weapon_type)})


func _on_ammo_paid(by: Player, ore_type: OreType, amount: float) -> void:
	if _is_mine(by):
		count("ore_for_ammo", [id_of(ore_type)], amount)


func _on_shield_blocked(by: Player, weapon_type: WeaponType, amount: float) -> void:
	if _is_mine(by):
		count("damage_blocked", [id_of(weapon_type)], amount)


func _on_dashed(by: Player) -> void:
	if _is_mine(by):
		count("dashes")
		_write_line("dashed", {})


func _on_player_hurt(hurt: Player, amount: float, cause: Node) -> void:
	if not _is_mine(hurt):
		return
	var label: String = cause_of(cause)
	count("damage_taken", [label], amount)
	var pending: Dictionary = _hurts.get_or_add(label, {"amount": 0.0, "hits": 0, "t": _time})
	pending["amount"] += amount
	pending["hits"] += 1


func _on_player_died(died: Player, cause: Node) -> void:
	if not _is_mine(died):
		return
	_log_hurts(true)
	var label: String = cause_of(cause)
	count("deaths", [label])
	_write_line(
		"player_died",
		{"cause": label, "weapon": id_of(player.weapon.type if player.weapon else null)}
	)


func _on_player_healed(healed: Player, amount: float) -> void:
	if _is_mine(healed):
		count("healed", [], amount)


func _on_player_respawned(respawned: Player) -> void:
	if _is_mine(respawned):
		count("respawns")
		_write_line("player_respawned", {})


func _on_miner_handled(by: Player, miner: Miner, counter: String, event: String) -> void:
	if _is_mine(by):
		count(counter)
		_write_line(event, {"ore": id_of(miner.ore_type), "crafted": miner.crafted != null})


func _on_miner_changed(miner: Miner, counter: String, event: String) -> void:
	if player and miner.fleet == player.fleet:
		count(counter)
		_write_line(event, {"ore": id_of(miner.ore_type), "crafted": miner.crafted != null})


func _on_ore(by: Player, ore_type: OreType, amount: float, counter: String, event: String) -> void:
	if not _is_mine(by):
		return
	count(counter, [id_of(ore_type)], amount)
	if event:
		_write_line(event, {"ore": id_of(ore_type), "amount": snappedf(amount, 0.01)})


func _on_weapon_gained(by: Player, weapon_type: WeaponType, counter: String, event: String) -> void:
	if _is_mine(by):
		count(counter, [id_of(weapon_type)])
		_write_line(event, {"weapon": id_of(weapon_type)})


func _on_upgrade_finished(by: Player, upgrade: Upgrade, mk: int) -> void:
	if _is_mine(by):
		count("upgrades_finished", [id_of(upgrade)])
		_write_line("upgrade_finished", {"upgrade": id_of(upgrade), "mk": mk})


func _on_skill_finished(by: Player, skill: Skill, rank: int) -> void:
	if _is_mine(by):
		count("skills_finished", [id_of(skill)])
		_write_line("skill_finished", {"skill": id_of(skill), "rank": rank})


func _on_bars_refined(by: Player, alloy: AlloyType, bars: int) -> void:
	if _is_mine(by):
		count("bars_refined", [id_of(alloy)], bars)
		_write_line("bars_refined", {"alloy": id_of(alloy), "bars": bars})


func _on_heat_shield_raised(mk: int) -> void:
	count("heat_shield_plates")
	_write_line("heat_shield_raised", {"mk": mk})


func _on_story_flag_set(flag: StringName) -> void:
	count("story_flags")
	_write_line("story_flag_set", {"flag": String(flag)})


func _on_mission_started(brief: MissionBrief) -> void:
	runs += 1
	run = StatCounters.new()
	_run_time = 0.0
	count("missions_started", [str(mission.tier()) if mission else "1"])
	var fields: Dictionary = {"tier": mission.tier() if mission else 1}
	if brief:
		var body: CelestialBody = null
		if brief.region and voyage and voyage.settings.system:
			body = voyage.settings.system.body_of(brief.region)
		(
			fields
			. merge(
				{
					"body": String(body.id) if body else "",
					"region": brief.region.display_name if brief.region else "",
					"biome": id_of(brief.biome),
					"difficulty": str(MissionBrief.Difficulty.keys()[brief.difficulty]).to_lower(),
					"length": brief.length,
					"seed": brief.world_seed,
				}
			)
		)
	if mission:
		fields["duration"] = snappedf(mission.duration(), 0.1)
	if player:
		fields["gear"] = _gear()
	_write_line("mission_started", fields)


func _on_storm_started() -> void:
	count("storms")
	_write_line("storm_started", {})


func _on_mission_ended(_brief: MissionBrief, returned: bool) -> void:
	_log_hurts(true)
	var result: String = "returned" if returned else "lost"
	count("missions_ended", [result])
	_write_line(
		"mission_ended",
		{
			"result": result,
			"seconds": snappedf(maxf(_run_time, 0.0), 0.1),
			"counters": run.to_data(),
		}
	)
	_run_time = -1.0
	save_totals()
	flush_log()


func _on_menu_opened(by: Player, menu: WorldMenu) -> void:
	if _is_mine(by):
		count("menus_opened", [id_of(menu)])
		_write_line("menu_opened", {"menu": id_of(menu)})


## What the player takes along: the loadout, upgrade levels, skill ranks and maximum health.
func _gear() -> Dictionary:
	var loadout: Array[String] = []
	for weapon_type: WeaponType in player.loadout.weapons:
		loadout.append(id_of(weapon_type))
	var upgrades: Dictionary = {}
	for upgrade: Upgrade in player.upgrades.levels:
		upgrades[id_of(upgrade)] = player.upgrades.levels[upgrade]
	var skills: Dictionary = {}
	for skill: Skill in player.skills.ranks:
		skills[id_of(skill)] = player.skills.ranks[skill]
	return {
		"loadout": loadout,
		"upgrades": upgrades,
		"skills": skills,
		"max_health": snappedf(player.max_health(), 0.1),
	}


## Counts the seconds and meters the player spends aboard, outside, in a menu or dead.
func _count_time(delta: float) -> void:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	var where: String = "outside"
	if player.dead:
		where = "dead"
	elif player.menu:
		where = "menu"
	elif ship and ship.is_aboard(player):
		where = "aboard"
	count("seconds", [where], delta)
	var position: Vector3 = player.global_position
	if _last_position != Vector3.INF and where in ["outside", "aboard"]:
		var moved: float = (
			Vector2(position.x - _last_position.x, position.z - _last_position.z).length()
		)
		if moved < TELEPORT_DISTANCE:
			count("meters", [where], moved)
	_last_position = position


## Logs the damage taken per cause that's older than `HURT_MERGE` (`all`: all of it).
func _log_hurts(all: bool) -> void:
	for label: String in _hurts.keys():
		var pending: Dictionary = _hurts[label]
		var since: float = pending["t"]
		if all or _time - since >= HURT_MERGE:
			var amount: float = pending["amount"]
			_write_line(
				"player_hurt",
				{"cause": label, "amount": snappedf(amount, 0.01), "hits": pending["hits"]},
				since
			)
			_hurts.erase(label)


## Logs `event` with `fields`, when it happened (`at`: seconds into the session; now by default)
## and in which run (with its time) while one is underway.
func _write_line(event: String, fields: Dictionary, at: float = -1.0) -> void:
	if not _log:
		return
	var line: Dictionary = {"t": snappedf(_time if at < 0.0 else at, 0.01), "e": event}
	if _run_time >= 0.0:
		line["run"] = runs
		line["run_t"] = snappedf(_run_time - (_time - at if at >= 0.0 else 0.0), 0.01)
	line.merge(fields)
	_log.store_line(JSON.stringify(line, "", false))


func _load_totals() -> void:
	var directory: String = stats_directory()
	if not directory:
		return
	var path: String = directory.path_join(TOTALS_FILE)
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	# Totals of an older version are read as they are, so raising `VERSION` keeps everyone's (a
	# change to a counter's meaning needs a step here); a newer game's aren't understood.
	var version: float = INF
	if data is Dictionary:
		var saved: Variant = (data as Dictionary).get("version")
		if saved is float or saved is int:
			version = saved
	if version > VERSION:
		push_warning("Stats: can't read %s, keeping it as %s.corrupt" % [path, TOTALS_FILE])
		DirAccess.rename_absolute(path, path + ".corrupt")
		return
	var counters: Variant = (data as Dictionary).get("counters", {})
	if counters is Dictionary:
		totals.from_data(counters as Dictionary)


## Opens this session's log, deleting the oldest ones beyond `KEEP_SESSIONS`.
func _open_log() -> void:
	var directory: String = stats_directory()
	if not directory:
		return
	var sessions: String = directory.path_join(SESSIONS_FOLDER)
	DirAccess.make_dir_recursive_absolute(sessions)
	var logs: Array[String] = []
	for file: String in DirAccess.get_files_at(sessions):
		if file.ends_with(".jsonl"):
			logs.append(file)
	logs.sort()
	while logs.size() >= KEEP_SESSIONS:
		var oldest: String = logs.pop_front()
		DirAccess.remove_absolute(sessions.path_join(oldest))
	var stamp: String = Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")
	var path: String = sessions.path_join(stamp + ".jsonl")
	_log = FileAccess.open(path, FileAccess.WRITE)
	if not _log:
		push_error("Stats: can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())])


## Logs the end of the session and writes everything (once).
func _end_session() -> void:
	if _log:
		_log_hurts(true)
		_write_line("session_ended", {"seconds": snappedf(_time, 0.1)})
		_log.close()
		_log = null
	if _dirty:
		save_totals()
