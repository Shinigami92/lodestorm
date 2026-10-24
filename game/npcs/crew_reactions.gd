class_name CrewReactions
extends Node
## The crew reacting to what happens, over the radio (see GAME_DESIGN.md, Spaceship: NPCs), the
## ship's: when an event (`EVENTS`) happens, one crew member with lines for it
## (`NpcProfile.reactions`) calls in (`transmit`), beside every player (`PlayerRadio`), or only
## the player it's about (a new weapon, waking after the first fall). With several crew members
## who have lines for it, they take turns; each says their lines in turn, worded for a player
## alone or for several together. One-time events (the first run won, the first fall, the first
## landing on a body) set a story flag (`event.<event>`, `event.landed.<body>`), so they come once
## per game. The storm warning goes only to the players outside.
## The turns and the biggest haul are the host's, saved with the ship.

## Emitted when what's saved changes.
signal changed

## The first run won: when everyone alive is back aboard.
const FIRST_RUN_WON: StringName = &"first_run_won"
## The first time a player fell: when they wake up in the medical bay (only to them).
const FIRST_DEATH: StringName = &"first_death"
## A new heat shield plate opened a planet (the subject: the planet's id).
const PLANET_OPENED: StringName = &"planet_opened"
## A player built a new weapon (only to them).
const WEAPON_BUILT: StringName = &"weapon_built"
## A run's whole haul beat the biggest so far by `BIG_HAUL_MARGIN`: when everyone is back aboard.
const BIG_HAUL: StringName = &"big_haul"
## The first player stepped out onto a planet or moon for the first time (the subject: its id).
const FIRST_LANDING: StringName = &"first_landing"
## The storm's warning started (only to the players outside).
const STORM_WARNING: StringName = &"storm_warning"
## Every event the crew calls in about.
const EVENTS: Array[StringName] = [
	FIRST_RUN_WON, FIRST_DEATH, PLANET_OPENED, WEAPON_BUILT, BIG_HAUL, FIRST_LANDING, STORM_WARNING
]
## How much bigger than the biggest so far a run's haul must be to count as big. TBD (playtest).
const BIG_HAUL_MARGIN: float = 1.25

## The ship whose crew calls.
var ship: Ship
## How many lines each crew member has said about each event ("<npc>.<event>"): the next in turn.
var said: Dictionary[StringName, int] = {}
## How many calls each event has had (by its name): whose turn it is among the crew with lines.
var turns: Dictionary[StringName, int] = {}
## The biggest haul of a run so far (all players' together, in units), 0 before the first won run.
var biggest_haul: float = 0.0

var _run_haul: float = 0.0
## Players whose first fall is called in once they wake up.
var _fallen: Array[Player] = []


func _ready() -> void:
	var events: GameEvents = GameEvents.bus
	events.mission_started.connect(_on_mission_started.unbind(1))
	events.ore_hauled.connect(_on_ore_hauled)
	events.mission_ended.connect(_on_mission_ended)
	events.player_died.connect(_on_player_died.unbind(1))
	events.player_respawned.connect(_on_player_respawned)
	events.heat_shield_raised.connect(_on_heat_shield_raised)
	events.weapon_unlocked.connect(_on_weapon_unlocked)
	events.storm_warned.connect(transmit.bind(STORM_WARNING))
	ship.player_left.connect(_on_player_left)


## Calls in about `event` (about `subject`): the crew member whose turn it is among those with
## lines for it says their next line to `to` alone, or else to every living player (only the ones
## outside for the storm warning). Nothing without lines or listeners.
func transmit(event: StringName, subject: StringName = &"", to: Player = null) -> void:
	var listeners: Array[Player] = []
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if player.dead or (to and player != to) or not player.radio.is_inside_tree():
			continue
		if event == STORM_WARNING and ship.is_aboard(player):
			continue
		listeners.append(player)
	if listeners.is_empty():
		return
	var together: bool = not to and get_tree().get_nodes_in_group(Player.GROUP).size() > 1
	var speakers: Array[Npc] = []
	for npc: Npc in crew():
		if not npc.profile.reaction_lines(event, subject, together).is_empty():
			speakers.append(npc)
	if speakers.is_empty():
		return
	var turn: int = turns.get(event, 0)
	turns[event] = turn + 1
	var speaker: NpcProfile = speakers[turn % speakers.size()].profile
	var english: String = next_line(speaker, event, subject, together)
	for player: Player in listeners:
		player.radio.hear(speaker, english, event)
	changed.emit()


## The next line in turn of `profile` for `event` about `subject` (English, worded for several
## players `together` or one), counted as said; "" without one.
func next_line(
	profile: NpcProfile, event: StringName, subject: StringName = &"", together: bool = false
) -> String:
	var lines: Array[String] = profile.reaction_lines(event, subject, together)
	if lines.is_empty():
		return ""
	var key := StringName("%s.%s" % [profile.id, event])
	var turn: int = said.get(key, 0)
	said[key] = turn + 1
	return lines[turn % lines.size()]


## The crew aboard: the ship's NPCs.
func crew() -> Array[Npc]:
	var found: Array[Npc] = []
	for node: Node in ship.find_children("*", "", true, false):
		var npc := node as Npc
		if npc and npc.profile:
			found.append(npc)
	return found


## Calls in about every event once (debug; queued one after another): the first planet inwards and
## the first body stand in for the subjects.
func transmit_all() -> void:
	transmit(FIRST_RUN_WON)
	transmit(BIG_HAUL)
	var local: Player = Player.first_local(get_tree())
	if local:
		transmit(FIRST_DEATH, &"", local)
		transmit(WEAPON_BUILT, &"", local)
	var system: StarSystem = ship.voyage.settings.system if ship.voyage else null
	if system:
		for body: CelestialBody in system.bodies:
			if body.tier == 2 and not body.orbits:
				transmit(PLANET_OPENED, body.id)
		transmit(FIRST_LANDING, system.bodies[0].id)
	transmit(STORM_WARNING)


## What's saved: the turns and the biggest haul.
func get_data() -> Dictionary:
	return {"said": _counts_data(said), "turns": _counts_data(turns), "biggest_haul": biggest_haul}


## Takes over what a save had (`get_data`); returns whether all of it was read (a broken entry is
## skipped).
func restore(data: Dictionary) -> bool:
	var complete: bool = _read_counts(data.get("said"), said)
	complete = _read_counts(data.get("turns"), turns) and complete
	var haul: Variant = data.get("biggest_haul", 0.0)
	var amount: float = type_convert(haul, TYPE_FLOAT) if haul is float or haul is int else 0.0
	biggest_haul = maxf(amount, 0.0)
	return complete


static func _counts_data(counts: Dictionary[StringName, int]) -> Dictionary:
	var saved: Dictionary = {}
	for key: StringName in counts:
		saved[String(key)] = counts[key]
	return saved


## Reads saved counts (`_counts_data`) into `counts`; returns whether every entry was whole.
static func _read_counts(saved: Variant, counts: Dictionary[StringName, int]) -> bool:
	counts.clear()
	if not saved is Dictionary:
		return saved == null
	var complete: bool = true
	var entries: Dictionary = saved
	for key: Variant in entries:
		var count: Variant = entries[key]
		var number: float = (
			type_convert(count, TYPE_FLOAT) if count is float or count is int else -1.0
		)
		if key is String and number >= 0.0:
			counts[StringName(key as String)] = roundi(number)
		else:
			complete = false
	return complete


## Sets the story flag of a one-time event; returns whether it wasn't set yet.
func _first(flag: StringName) -> bool:
	if ship.story.is_set(flag):
		return false
	ship.story.set_flag(flag)
	return true


func _on_mission_started() -> void:
	_run_haul = 0.0


func _on_ore_hauled(_player: Player, _ore_type: OreType, amount: float) -> void:
	_run_haul += amount


func _on_mission_ended(_brief: MissionBrief, returned: bool) -> void:
	var haul: float = _run_haul
	_run_haul = 0.0
	if not returned:
		return
	if _first(&"event.first_run_won"):
		transmit(FIRST_RUN_WON)
	if haul <= 0.0:
		return
	if biggest_haul > 0.0 and haul >= biggest_haul * BIG_HAUL_MARGIN:
		transmit(BIG_HAUL)
	if haul > biggest_haul:
		biggest_haul = haul
		changed.emit()


func _on_player_died(player: Player) -> void:
	if _first(&"event.first_death"):
		_fallen.append(player)


func _on_player_respawned(player: Player) -> void:
	if player in _fallen:
		_fallen.erase(player)
		transmit(FIRST_DEATH, &"", player)


## The planet the new plate opened: the one of its tier around the star.
func _on_heat_shield_raised(mk: int) -> void:
	var system: StarSystem = ship.voyage.settings.system if ship.voyage else null
	if not system:
		return
	for body: CelestialBody in system.bodies:
		if body.tier == mk and not body.orbits:
			transmit(PLANET_OPENED, body.id)


func _on_weapon_unlocked(player: Player, _weapon_type: WeaponType) -> void:
	transmit(WEAPON_BUILT, &"", player)


## The first player to step out onto a body nobody has walked on yet (not one leaving the tree, e.g.
## while the map closes: its radio has gone first).
func _on_player_left(player: Player) -> void:
	if not player.radio.is_inside_tree():
		return
	var body: CelestialBody = ship.voyage.at_body if ship.voyage else null
	if not body or body.kind == CelestialBody.Kind.STATION:
		return
	if _first(StringName("event.landed.%s" % body.id)):
		transmit(FIRST_LANDING, body.id)
