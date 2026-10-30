class_name SaveGame
extends Node
## Keeps the progress between sessions in one save: the host's (the ship's story flags, heat
## shield, furnaces unlocked, cradles open, crew reactions and quests, where it is) in `ship.json`
## and the local player's (their health, hold, batches in the furnaces, weapons and blueprints,
## loadout, upgrade levels, skill ranks, crafted miners, hints seen and jobs finished since the
## quest board showed them) in `player.json`, both in `save/` under `directory`. It loads them when
## the map starts and saves whenever progress changes while no mission is underway; what changes
## during a mission is saved once it's over (returned or lost), so quitting mid-mission loses that
## run like dying. The settings (`GameSettings`) are kept apart and survive `reset_progress`.
## Every saved system writes and reads its own part (`save_data`, `load_data`, see `SaveData`);
## this only puts the parts together under their keys. Entries that don't read are skipped, and a
## file that can't be read or is of another version is kept as `<name>.corrupt` while the game
## starts from the defaults (no older saves are converted before the release).

const GROUP: StringName = &"save_games"
## The save format; raise it when the format changes (older saves start over).
const VERSION: int = 6
const SHIP_FILE: String = "ship.json"
const PLAYER_FILE: String = "player.json"

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
## Where the ship goes: where it is is saved, and so is setting course.
@export var voyage: Voyage

## Whether a save is queued for the end of the frame.
var _save_queued: bool = false
## Off after `reset_progress`, so nothing is written until the map reloads.
var _active: bool = true
## Whether the save just read had to be repaired, so it's written again right away.
var _outdated: bool = false
## Whether the player's health was full when it last changed.
var _was_healed: bool = true


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
	if not voyage:
		voyage = get_tree().get_first_node_in_group(Voyage.GROUP) as Voyage
	load_progress()
	if ship:
		ship.story.changed.connect(_on_progress_changed)
		ship.heat_shield.changed.connect(_on_progress_changed)
		ship.furnaces.changed.connect(_on_progress_changed)
		ship.cradles.changed.connect(_on_progress_changed)
		ship.reactions.changed.connect(_on_progress_changed)
		ship.quests.changed.connect(_on_progress_changed)
	if player:
		player.hold.changed.connect(_on_progress_changed)
		player.refining.changed.connect(_on_progress_changed)
		player.arsenal.changed.connect(_on_progress_changed)
		player.loadout.changed.connect(_on_progress_changed)
		player.upgrades.changed.connect(_on_progress_changed)
		player.skills.changed.connect(_on_progress_changed)
		player.fleet.changed.connect(_on_progress_changed)
		player.hints.changed.connect(_on_progress_changed)
		player.finished_jobs.changed.connect(_on_progress_changed)
		player.health_changed.connect(_on_health_changed)
	if voyage:
		voyage.selected.connect(_on_progress_changed.unbind(1))
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


## What's saved of `of_ship` (see each part's `save_data`).
static func ship_data(of_ship: Ship) -> Dictionary:
	return {
		"version": VERSION,
		"story": of_ship.story.save_data(),
		"shield": of_ship.heat_shield.save_data(),
		"furnaces": of_ship.furnaces.save_data(),
		"cradles": of_ship.cradles.save_data(),
		"reactions": of_ship.reactions.save_data(),
		"quests": of_ship.quests.save_data(),
		"at": of_ship.voyage.save_data() if of_ship.voyage else null,
	}


## What's saved of `of_player` (see each part's `save_data`); its health is full when it's dead
## (it respawns with full health).
static func player_data(of_player: Player) -> Dictionary:
	return {
		"version": VERSION,
		"health": of_player.max_health() if of_player.fallen else of_player.health,
		"hold": of_player.hold.save_data(),
		"refining": of_player.refining.save_data(),
		"arsenal": of_player.arsenal.save_data(),
		"loadout": of_player.loadout.save_data(),
		"upgrades": of_player.upgrades.save_data(),
		"skills": of_player.skills.save_data(),
		"fleet": of_player.fleet.save_data(),
		"hints": of_player.hints.save_data(),
		"finished": of_player.finished_jobs.save_data(),
	}


func _apply_ship(data: Dictionary) -> void:
	_loaded(ship.story.load_data(data.get("story")))
	_loaded(ship.heat_shield.load_data(data.get("shield")))
	_loaded(ship.furnaces.load_data(data.get("furnaces")))
	_loaded(ship.cradles.load_data(data.get("cradles")))
	_loaded(ship.reactions.load_data(data.get("reactions")))
	_loaded(ship.quests.load_data(data.get("quests")))
	# After the heat shield: the ship stays only where it reaches.
	if voyage:
		_loaded(voyage.load_data(data.get("at")))


func _apply_player(data: Dictionary) -> void:
	_loaded(player.hold.load_data(data.get("hold")))
	_loaded(player.refining.load_data(data.get("refining")))
	_loaded(player.arsenal.load_data(data.get("arsenal")))
	_loaded(player.loadout.load_data(data.get("loadout"), player.arsenal))
	_loaded(player.upgrades.load_data(data.get("upgrades")))
	_loaded(player.skills.load_data(data.get("skills")))
	_loaded(player.fleet.load_data(data.get("fleet")))
	_loaded(player.hints.load_data(data.get("hints")))
	_loaded(player.finished_jobs.load_data(data.get("finished")))
	# After the upgrades and skills (they set the maximum), before the jobs done since take effect
	# (one adds its difference, as it would have in the game). A save without it keeps full health.
	if data.has("health"):
		var health: float = SaveData.number(data["health"], player.max_health())
		player.vitals.restore(health if health > 0.0 else player.max_health())
	var now: float = Time.get_unix_time_from_system()
	player.refining.update(player.hold, now)
	player.upgrades.update(now)
	player.skills.update(now)
	player.fleet.update(now)


## Notes a part that didn't read whole, so the repaired save is written again.
func _loaded(complete: bool) -> void:
	_outdated = _outdated or not complete


## The data in save file `file_name`, empty when there's none or it can't be read or is of another
## version (then it's kept as `<file_name>.corrupt`, and the next save starts over).
func _read(file_name: String) -> Dictionary:
	var path: String = save_directory().path_join(file_name)
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	var data: Variant = null
	if json.parse(FileAccess.get_file_as_string(path)) == OK:
		data = json.data
	if data is Dictionary and SaveData.number((data as Dictionary).get("version"), 0.0) == VERSION:
		return data
	push_error("Save: can't read %s (broken or another version), starting from the defaults" % path)
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


## Health changes all the time while it heals (a med bed, regeneration), so it's saved once it's
## full again (and with any other progress).
func _on_health_changed(health: float) -> void:
	var healed: bool = health >= player.max_health()
	if healed and not _was_healed:
		_on_progress_changed()
	_was_healed = healed
