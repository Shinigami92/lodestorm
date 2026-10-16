class_name SaveGame
extends Node
## Keeps the progress between sessions in one save: the host's (the ship's hold and the story's
## flags, later crew and quests) in `ship.json` and the local player's (owned weapons, loadout,
## upgrade levels, skill ranks) in `player.json`, both in `save/` under `directory`. It loads
## them when the map starts and saves whenever progress changes while no mission is underway;
## what changes during a mission is saved once it's over (returned or lost), so quitting
## mid-mission loses that run like dying. The settings (`GameSettings`) are kept apart and survive
## `reset_progress`.
## Resources (ore types, weapons, upgrades, skills) are saved by their path, so moving or renaming
## one of them needs a migration (`VERSION`). Unknown entries are skipped; a file that can't be
## read is kept as `<name>.corrupt` and the game starts from the defaults.

const GROUP: StringName = &"save_games"
## The save format; raise it (and convert older saves in `_read`) when the format changes.
const VERSION: int = 1
const SHIP_FILE: String = "ship.json"
## Resources that were renamed: their old path in older saves, and the new one.
const RENAMED: Dictionary[String, String] = {
	"res://game/ores/types/ore_kyrite.tres": "res://game/ores/types/ore_kyrite.tres",
	"res://game/ores/types/ore_olvane.tres": "res://game/ores/types/ore_olvane.tres",
	"res://game/ores/types/ore_vyrel.tres": "res://game/ores/types/ore_vyrel.tres",
}
const PLAYER_FILE: String = "player.json"

## Where the saves and the settings go: the user data folder, or a `dev/` folder in it for runs
## from the editor, so debug shortcuts (unlock weapons, fill hold) never reach a real save. Empty:
## nothing is loaded or saved (the tests, `tests/support/pre_run.gd`).
static var directory: String = "user://dev/" if OS.has_feature("editor") else "user://"

## The ship whose hold is saved.
@export var ship: Ship
## The player whose gear is saved (the local one).
@export var player: Player
## The mission; progress changed while it's underway is saved when it's over.
@export var mission: Mission

## Whether a save is queued for the end of the frame.
var _save_queued: bool = false
## Off after `reset_progress`, so nothing is written until the map reloads.
var _active: bool = true


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
		ship.hold_changed.connect(_on_progress_changed.unbind(2))
		ship.story.changed.connect(_on_progress_changed)
	if player:
		player.arsenal.changed.connect(_on_progress_changed)
		player.loadout.changed.connect(_on_progress_changed)
		player.upgrades.changed.connect(_on_progress_changed)
		player.skills.changed.connect(_on_progress_changed)
	if mission:
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


## What's saved of `ship`: the hold, in units per ore type, the ores ever brought aboard and the
## story's flags.
static func ship_data(of_ship: Ship) -> Dictionary:
	var hold: Dictionary = {}
	for ore_type: OreType in of_ship.hold:
		hold[ore_type.resource_path] = of_ship.hold[ore_type]
	var found: Array = []
	for ore_type: OreType in of_ship.found_ores:
		found.append(ore_type.resource_path)
	found.sort()
	var flags: Array = []
	for flag: StringName in of_ship.story.flags:
		flags.append(String(flag))
	flags.sort()
	return {"version": VERSION, "hold": hold, "found": found, "story": flags}


## What's saved of `of_player`: the weapons it owns, its loadout (null: empty slot), the MK
## level of each upgrade it bought and the rank of each skill it learned.
static func player_data(of_player: Player) -> Dictionary:
	var weapons: Array = []
	for weapon_type: WeaponType in of_player.arsenal.weapons:
		weapons.append(weapon_type.resource_path)
	var loadout: Array = []
	for weapon_type: WeaponType in of_player.loadout.weapons:
		loadout.append(weapon_type.resource_path if weapon_type else null)
	var levels: Dictionary = {}
	for upgrade: Upgrade in of_player.upgrades.levels:
		levels[upgrade.resource_path] = of_player.upgrades.levels[upgrade]
	var ranks: Dictionary = {}
	for skill: Skill in of_player.skills.ranks:
		ranks[skill.resource_path] = of_player.skills.ranks[skill]
	return {
		"version": VERSION,
		"arsenal": weapons,
		"loadout": loadout,
		"upgrades": levels,
		"skills": ranks,
	}


func _apply_ship(data: Dictionary) -> void:
	var hold: Dictionary = data.get("hold", {})
	for path: Variant in hold:
		var ore_type := _resource(path) as OreType
		var amount: float = _number(hold[path], -1.0)
		if ore_type and amount >= 0.0:
			ship.add_to_hold(ore_type, amount)
		else:
			push_warning("Save: skipped hold entry %s" % path)
	if data.get("found") is Array:
		for path: Variant in data["found"] as Array:
			var ore_type := _resource(path) as OreType
			if ore_type:
				ship.mark_found(ore_type)
			else:
				push_warning("Save: skipped found ore %s" % path)
	if data.get("story") is Array:
		for flag: Variant in data["story"] as Array:
			if flag is String and not (flag as String).is_empty():
				ship.story.flags[StringName(flag as String)] = true
			else:
				push_warning("Save: skipped story flag %s" % flag)
		ship.story.emit_changed()


func _apply_player(data: Dictionary) -> void:
	if data.has("arsenal"):
		var weapons: Array[WeaponType] = []
		for path: Variant in data["arsenal"] as Array:
			var weapon_type := _resource(path) as WeaponType
			if weapon_type and weapon_type not in weapons:
				weapons.append(weapon_type)
			else:
				push_warning("Save: skipped weapon %s" % path)
		player.arsenal.weapons = weapons
		player.arsenal.emit_changed()
	if data.has("loadout"):
		var slots: Array = data["loadout"]
		for slot: int in slots.size():
			var weapon_type := _resource(slots[slot]) as WeaponType
			# Only owned weapons; anything else leaves the slot empty.
			player.loadout.assign(
				slot, weapon_type if weapon_type and player.arsenal.owns(weapon_type) else null
			)
	if data.has("upgrades"):
		var levels: Dictionary = data["upgrades"]
		for path: Variant in levels:
			var upgrade := _resource(path) as Upgrade
			var mk: float = _number(levels[path], 0.0)
			if upgrade and mk >= 1.0:
				player.upgrades.levels[upgrade] = clampi(roundi(mk), 1, upgrade.max_mk())
			else:
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
				push_warning("Save: skipped skill %s" % path)
		player.skills.emit_changed()


## The project resource at `path` from a save, or null for anything else.
static func _resource(path: Variant) -> Resource:
	if not path is String:
		return null
	var res_path: String = RENAMED.get(path, path)
	if not res_path.begins_with("res://") or not ResourceLoader.exists(res_path):
		return null
	return load(res_path)


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
