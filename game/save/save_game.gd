class_name SaveGame
extends Node
## Keeps the progress between sessions in one save: the host's (the ship's heat shield, where it
## is, the story's flags and the furnaces unlocked, later crew and quests) in `ship.json` and the
## local player's (their hold, their batches in the furnaces, owned weapons and blueprints, loadout,
## upgrade levels, skill ranks) in `player.json`,
## both in `save/` under `directory`. It loads
## them when the map starts and saves whenever progress changes while no mission is underway;
## what changes during a mission is saved once it's over (returned or lost), so quitting
## mid-mission loses that run like dying. The settings (`GameSettings`) are kept apart and survive
## `reset_progress`.
## Resources (ore types, weapons, upgrades, skills) are saved by their UID, so they can be moved
## and renamed; saves of version 1 named them by path, which `MOVED` follows. Unknown entries are
## skipped, and a save without a known weapon keeps the default arsenal and loadout; a file that
## can't be read is kept as `<name>.corrupt` and the game starts from the defaults. Up to version 2
## the hold was the ship's: it moves from `ship.json` into `player.json`.

const GROUP: StringName = &"save_games"
## The save format; raise it (and convert older saves in `_read`) when the format changes.
const VERSION: int = 3
const SHIP_FILE: String = "ship.json"
const PLAYER_FILE: String = "player.json"
## Where resources named by path in version 1 saves went: a file, or a folder (ending in "/") and
## everything in it.
const MOVED: Dictionary[String, String] = {
	"res://scenes/mining/ores/ore_cyan.tres": "res://game/ores/types/ore_kyrite.tres",
	"res://scenes/mining/ores/ore_green.tres": "res://game/ores/types/ore_olvane.tres",
	"res://scenes/mining/ores/ore_violet.tres": "res://game/ores/types/ore_vyrel.tres",
	"res://scenes/mining/ores/": "res://game/ores/types/",
	"res://scenes/weapons/types/blaster.tres": "res://game/weapons/types/harl/harl.tres",
	"res://scenes/weapons/types/shotgun.tres": "res://game/weapons/types/brask/brask.tres",
	"res://scenes/weapons/types/hammer.tres": "res://game/weapons/types/dray/dray.tres",
	"res://scenes/weapons/types/": "res://game/weapons/types/",
	"res://scenes/upgrades/blaster.tres": "res://game/weapons/types/harl/mk_damage.tres",
	"res://scenes/upgrades/blaster_magazine.tres": "res://game/weapons/types/harl/mk_magazine.tres",
	"res://scenes/upgrades/shotgun.tres": "res://game/weapons/types/brask/mk_damage.tres",
	"res://scenes/upgrades/shotgun_magazine.tres":
	"res://game/weapons/types/brask/mk_magazine.tres",
	"res://scenes/upgrades/hammer.tres": "res://game/weapons/types/dray/mk_damage.tres",
	"res://scenes/upgrades/": "res://game/progression/upgrades/",
	"res://scenes/skills/": "res://game/progression/skills/tree/",
}

## Where the saves and the settings go: the user data folder, or a `dev/` folder in it for runs
## from the editor, so debug shortcuts (unlock weapons, fill hold) never reach a real save. Empty:
## nothing is loaded or saved (the tests, `tests/support/pre_run.gd`).
static var directory: String = "user://dev/" if OS.has_feature("editor") else "user://"

## The ship whose state is saved.
@export var ship: Ship
## The player whose gear is saved (the local one).
@export var player: Player
## The mission; progress changed while it's underway is saved when it's over.
@export var mission: Mission

## Whether a save is queued for the end of the frame.
var _save_queued: bool = false
## Off after `reset_progress`, so nothing is written until the map reloads.
var _active: bool = true
## Whether the save just read was older or had to be repaired, so it's written again right away.
var _outdated: bool = false
## The hold a `ship.json` before version 3 had (`hold`, `found`), for the player's save to take.
var _ship_hold: Dictionary = {}


## The folder of the save (empty when saving is off).
static func save_directory() -> String:
	return directory.path_join("save") if directory else ""


## Whether there's a save to load.
static func exists() -> bool:
	return directory != "" and DirAccess.dir_exists_absolute(save_directory())


## Deletes the save (not the settings). Irreversible.
static func erase() -> void:
	if not exists():
		return
	var dir: String = save_directory()
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _enter_tree() -> void:
	# Before the other nodes are ready, so menus build in the saved language.
	GameSettings.load_settings()


func _ready() -> void:
	add_to_group(GROUP)
	if not mission:
		mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	load_progress()
	if ship:
		ship.story.changed.connect(_on_progress_changed)
		ship.heat_shield.changed.connect(_on_progress_changed)
		ship.furnaces.changed.connect(_on_progress_changed)
	if player:
		player.hold.changed.connect(_on_progress_changed)
		player.refining.changed.connect(_on_progress_changed)
		player.arsenal.changed.connect(_on_progress_changed)
		player.loadout.changed.connect(_on_progress_changed)
		player.upgrades.changed.connect(_on_progress_changed)
		player.skills.changed.connect(_on_progress_changed)
	if mission:
		mission.selected.connect(_on_progress_changed.unbind(1))
		mission.returned.connect(save_progress)
		mission.lost.connect(save_progress)


## Reads the save into the ship and the player (nothing happens without one).
func load_progress() -> void:
	if not directory:
		return
	if ship:
		_apply_ship(_read(SHIP_FILE))
	if player:
		_apply_player(_read(PLAYER_FILE))
	if _outdated:
		_outdated = false
		_on_progress_changed()


## Writes the ship's and the player's progress (nothing happens while saving is off).
func save_progress() -> void:
	_save_queued = false
	if not directory or not _active:
		return
	DirAccess.make_dir_recursive_absolute(save_directory())
	if ship:
		_write(SHIP_FILE, ship_data(ship))
	if player:
		_write(PLAYER_FILE, player_data(player))


## Whether the player is alone: nobody else in the session (no connected peers, one player).
## Friends can join any time, so hosting a session alone counts too. Only then can the progress be
## reset; with others in the session, everyone keeps theirs.
static func is_solo(tree: SceneTree) -> bool:
	return (
		tree.get_multiplayer().get_peers().is_empty()
		and tree.get_nodes_in_group(Player.GROUP).size() <= 1
	)


## Wipes the progress and starts over from the defaults: deletes the save and reloads the map
## (when it's the current scene). Irreversible; the settings stay. Only while the player is alone
## (`is_solo`); returns whether it reset.
func reset_progress() -> bool:
	if not is_solo(get_tree()):
		return false
	_active = false
	erase()
	if get_parent() == get_tree().current_scene:
		get_tree().reload_current_scene.call_deferred()
	return true


## What's saved of `ship`: the story's flags, the heat shield (its MK level, whether the next
## plate is the ship's project and what's paid into it), the furnaces unlocked and the body the
## ship is at (its id; none before the first flight).
static func ship_data(of_ship: Ship) -> Dictionary:
	var flags: Array = []
	for flag: StringName in of_ship.story.flags:
		flags.append(String(flag))
	flags.sort()
	var shield: HeatShield = of_ship.heat_shield
	var paid: Dictionary = {}
	for ore_type: OreType in shield.paid:
		paid[_reference(ore_type)] = shield.paid[ore_type]
	var data: Dictionary = {
		"version": VERSION,
		"story": flags,
		"shield": {"mk": shield.mk, "project": shield.project, "paid": paid},
		"furnaces": of_ship.furnaces.unlocked,
	}
	if of_ship.mission and of_ship.mission.at_body:
		data["at"] = String(of_ship.mission.at_body.id)
	return data


## What's saved of `of_player`: its hold (units per item, the items ever in it), its batches in
## the furnaces (per batch its furnace slot, the alloy, the bars, how many are done and when it
## started in Unix seconds), the weapons it owns and its blueprints, its loadout (null: empty
## slot), the MK level of each upgrade it bought and the rank of each skill it learned.
static func player_data(of_player: Player) -> Dictionary:
	var hold: Dictionary = {}
	for item: ItemType in of_player.hold.items:
		hold[_reference(item)] = of_player.hold.items[item]
	var found: Array = []
	for item: ItemType in of_player.hold.found:
		found.append(_reference(item))
	found.sort()
	var refining: Array = []
	for slot: int in Refining.SLOTS:
		var batch: AlloyBatch = of_player.refining.get_batch(slot)
		if batch:
			(
				refining
				. append(
					{
						"slot": slot,
						"alloy": _reference(batch.alloy),
						"bars": batch.bars,
						"done": batch.done,
						"started": batch.started,
					}
				)
			)
	var weapons: Array = []
	for weapon_type: WeaponType in of_player.arsenal.weapons:
		weapons.append(_reference(weapon_type))
	var blueprints: Array = []
	for weapon_type: WeaponType in of_player.arsenal.blueprints:
		blueprints.append(_reference(weapon_type))
	var loadout: Array = []
	for weapon_type: WeaponType in of_player.loadout.weapons:
		if weapon_type:
			loadout.append(_reference(weapon_type))
		else:
			loadout.append(null)
	var levels: Dictionary = {}
	for upgrade: Upgrade in of_player.upgrades.levels:
		levels[_reference(upgrade)] = of_player.upgrades.levels[upgrade]
	var ranks: Dictionary = {}
	for skill: Skill in of_player.skills.ranks:
		ranks[_reference(skill)] = of_player.skills.ranks[skill]
	return {
		"version": VERSION,
		"hold": hold,
		"found": found,
		"refining": refining,
		"arsenal": weapons,
		"blueprints": blueprints,
		"loadout": loadout,
		"upgrades": levels,
		"skills": ranks,
	}


func _apply_ship(data: Dictionary) -> void:
	_ship_hold = {}
	if data.has("hold") or data.has("found"):
		# Before version 3 the hold was the ship's: the player's save takes it.
		_outdated = true
		_ship_hold = {"hold": data.get("hold", {}), "found": data.get("found", [])}
	if data.get("story") is Array:
		for flag: Variant in data["story"] as Array:
			if flag is String and not (flag as String).is_empty():
				ship.story.flags[StringName(flag as String)] = true
			else:
				_outdated = true
				push_warning("Save: skipped story flag %s" % flag)
		ship.story.emit_changed()
	if data.get("shield") is Dictionary:
		_apply_shield(data["shield"] as Dictionary)
	if data.has("furnaces"):
		var count: float = _number(data["furnaces"], -1.0)
		if count < 0.0 or count > Refining.SLOTS:
			_outdated = true
			push_warning("Save: skipped furnaces %s" % data["furnaces"])
		ship.furnaces.restore(roundi(clampf(count, 0.0, Refining.SLOTS)))
	if data.has("at"):
		_apply_position(data["at"])


func _apply_shield(data: Dictionary) -> void:
	var mk: float = _number(data.get("mk"), 0.0)
	if mk < 1.0 or mk > ship.heat_shield.max_mk():
		_outdated = true
		push_warning("Save: skipped heat shield level %s" % data.get("mk"))
		mk = clampf(mk, 1.0, ship.heat_shield.max_mk())
	var paid: Dictionary[OreType, float] = {}
	var saved_paid: Dictionary = {}
	if data.get("paid") is Dictionary:
		saved_paid = data["paid"]
	for path: Variant in saved_paid:
		var ore_type := _resource(path) as OreType
		var amount: float = _number(saved_paid[path], -1.0)
		if ore_type and amount >= 0.0:
			paid[ore_type] = amount
		else:
			_outdated = true
			push_warning("Save: skipped heat shield payment %s" % path)
	var is_project: bool = false
	if data.get("project") is bool:
		is_project = data["project"]
	ship.heat_shield.restore(roundi(mk), is_project, paid)


## Puts the ship at the body a save names, if the heat shield reaches it.
func _apply_position(id: Variant) -> void:
	var system: StarSystem = mission.settings.system if mission and mission.settings else null
	var body: CelestialBody = null
	if id is String and system:
		body = system.body_by_id(StringName(id as String))
	if body and body.is_reachable(ship.heat_shield.mk) and mission:
		mission.at_body = body
	else:
		_outdated = true
		push_warning("Save: skipped the ship's position %s" % id)


func _apply_player(data: Dictionary) -> void:
	if not data.has("hold") and not _ship_hold.is_empty():
		data = data.duplicate()
		data.merge(_ship_hold)
	_apply_hold(data)
	if data.get("refining") is Array:
		_apply_refining(data["refining"] as Array)
	if data.get("arsenal") is Array:
		var weapons: Array[WeaponType] = []
		for path: Variant in data["arsenal"] as Array:
			var weapon_type := _resource(path) as WeaponType
			if weapon_type and weapon_type not in weapons:
				weapons.append(weapon_type)
			else:
				_outdated = true
				push_warning("Save: skipped weapon %s" % path)
		# Weapons are never taken away, so a save without any is damaged: keep the default ones.
		if weapons.is_empty():
			_outdated = true
			push_warning("Save: no known weapon, keeping the default arsenal")
		else:
			player.arsenal.weapons = weapons
			player.arsenal.emit_changed()
	if data.get("blueprints") is Array:
		var blueprints: Array[WeaponType] = []
		for path: Variant in data["blueprints"] as Array:
			var weapon_type := _resource(path) as WeaponType
			if weapon_type and weapon_type not in blueprints:
				if not player.arsenal.owns(weapon_type):
					blueprints.append(weapon_type)
			else:
				_outdated = true
				push_warning("Save: skipped blueprint %s" % path)
		player.arsenal.blueprints = blueprints
		player.arsenal.emit_changed()
	if data.get("loadout") is Array:
		# Only owned weapons; anything else leaves the slot empty.
		var slots: Array[WeaponType] = []
		for path: Variant in data["loadout"] as Array:
			var weapon_type := _resource(path) as WeaponType
			slots.append(weapon_type if weapon_type and player.arsenal.owns(weapon_type) else null)
		# The locker never empties the loadout, so a save that does keeps the default one.
		if slots.any(func(weapon_type: WeaponType) -> bool: return weapon_type != null):
			for slot: int in slots.size():
				player.loadout.assign(slot, slots[slot])
		else:
			_outdated = true
			push_warning("Save: no owned weapon in the loadout, keeping the default one")
			for slot: int in player.loadout.weapons.size():
				if not player.arsenal.owns(player.loadout.get_weapon(slot)):
					player.loadout.assign(slot, null)
	if data.has("upgrades"):
		var levels: Dictionary = data["upgrades"]
		for path: Variant in levels:
			var upgrade := _resource(path) as Upgrade
			var mk: float = _number(levels[path], 0.0)
			if upgrade and mk >= 1.0:
				player.upgrades.levels[upgrade] = clampi(roundi(mk), 1, upgrade.max_mk())
			else:
				_outdated = true
				push_warning("Save: skipped upgrade %s" % path)
		player.upgrades.emit_changed()
	if data.has("skills"):
		var ranks: Dictionary = data["skills"]
		for path: Variant in ranks:
			var skill := _resource(path) as Skill
			var rank: float = _number(ranks[path], 0.0)
			if skill and rank >= 1.0:
				player.skills.ranks[skill] = clampi(roundi(rank), 1, skill.max_rank())
			else:
				_outdated = true
				push_warning("Save: skipped skill %s" % path)
		player.skills.emit_changed()


## Reads a player's hold: units per item (`hold`) and the items ever in it (`found`).
func _apply_hold(data: Dictionary) -> void:
	var hold: Dictionary = {}
	if data.get("hold") is Dictionary:
		hold = data["hold"]
	for path: Variant in hold:
		var item := _resource(path) as ItemType
		var amount: float = _number(hold[path], -1.0)
		if item and amount >= 0.0:
			player.hold.add(item, amount)
		else:
			_outdated = true
			push_warning("Save: skipped hold entry %s" % path)
	if data.get("found") is Array:
		for path: Variant in data["found"] as Array:
			var item := _resource(path) as ItemType
			if item:
				player.hold.mark_found(item)
			else:
				_outdated = true
				push_warning("Save: skipped found item %s" % path)


## Reads a player's batches in the furnaces and puts every bar finished since into the hold.
func _apply_refining(batches: Array) -> void:
	for entry: Variant in batches:
		var batch: AlloyBatch = null
		var slot: int = -1
		if entry is Dictionary:
			var saved: Dictionary = entry
			var alloy := _resource(saved.get("alloy")) as AlloyType
			var bars: int = roundi(_number(saved.get("bars"), 0.0))
			var done: int = roundi(_number(saved.get("done"), -1.0))
			var started: float = _number(saved.get("started"), NAN)
			slot = roundi(_number(saved.get("slot"), -1.0))
			var free: bool = (
				slot >= 0 and slot < Refining.SLOTS and not player.refining.get_batch(slot)
			)
			if alloy and free and bars >= 1 and done >= 0 and done < bars and not is_nan(started):
				batch = AlloyBatch.new(alloy, bars, started)
				batch.done = done
		if batch:
			player.refining.restore(slot, batch)
		else:
			_outdated = true
			push_warning("Save: skipped refining batch %s" % entry)
	player.refining.update(player.hold, Time.get_unix_time_from_system())


## How a save names `resource`: its UID (its path if it has none).
static func _reference(resource: Resource) -> String:
	return ResourceUID.path_to_uid(resource.resource_path)


## The project resource a save names with `reference` (a UID, or a path in version 1 saves), or
## null for anything else.
static func _resource(reference: Variant) -> Resource:
	if not reference is String:
		return null
	var path: String = reference
	if path.begins_with("res://"):
		path = _moved(path)
	elif not path.begins_with("uid://"):
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## Where the resource a version 1 save named `path` is now.
static func _moved(path: String) -> String:
	if path in MOVED:
		return MOVED[path]
	for old: String in MOVED:
		if old.ends_with("/") and path.begins_with(old):
			return MOVED[old] + path.trim_prefix(old)
	return path


## `value` from a save as a number, or `fallback` when it isn't one.
static func _number(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var number: float = value
		return number
	return fallback


## The data in save file `file_name`, empty when there's none or it can't be read (then it's
## kept as `<file_name>.corrupt`, and the next save starts over).
func _read(file_name: String) -> Dictionary:
	var path: String = save_directory().path_join(file_name)
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	var data: Variant = null
	if json.parse(FileAccess.get_file_as_string(path)) == OK:
		data = json.data
	if data is Dictionary:
		var version: float = _number((data as Dictionary).get("version"), INF)
		if version <= VERSION:
			_outdated = _outdated or version < VERSION
			return data
	push_error("Save: can't read %s, starting from the defaults" % path)
	DirAccess.rename_absolute(path, path + ".corrupt")
	return {}


## Writes `data` to save file `file_name`, through a temporary file so a crash mid-write
## doesn't leave half a save.
func _write(file_name: String, data: Dictionary) -> void:
	var path: String = save_directory().path_join(file_name)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file:
		push_error("Save: can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)


func _on_progress_changed() -> void:
	if mission and mission.is_underway():
		return
	if not _save_queued:
		_save_queued = true
		save_progress.call_deferred()
