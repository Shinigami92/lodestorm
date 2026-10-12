class_name Mission
extends Node
## The mission loop around the ship. The holo table offers a few missions (`offers`); picking one
## (`select`) replaces the outside world (`location`) with a fresh one of the mission's biome and
## seed and sets the timer (`duration`). The ramp starts closed; the ramp button inside the ship
## only works with a mission picked: it resets the timer, heals the players, lowers the ramp and
## locks the mission. The mission starts when the first player steps out; the timer then counts
## down, and at zero the storm hits (`time_up`) and hurts everyone outside, more with every
## second. Players who die drop what they carried.
## The mission is won (`returned`) once every living player is back aboard, in time or during the
## storm: their cargo goes into the ship's hold, the dead respawn aboard and the ramp goes up.
## It's lost (`lost`) when nobody is left alive; after `settings.respawn_delay` everyone respawns
## aboard. Either way the mission is done: new ones are offered, and the button starts the next
## run once one is picked. Players who die while no mission runs (e.g. killed through the debug
## overlay) also respawn aboard after `settings.respawn_delay`.
## Changing `settings.duration` while playing (debug overlay) updates the timer: before the start
## it's the new duration, while it runs it moves by the difference.

## Emitted when the missions on offer or the picked one change.
signal offers_changed
## Emitted when a mission is picked: the outside world is its location now.
signal selected(brief: MissionBrief)
## Emitted when the ramp button starts a new run: timer reset, the picked mission locked.
signal opened
## Emitted once per run when the first player steps out of the ship.
signal started
## Emitted once per run when the timer runs out.
signal time_up
## Emitted once per run when every living player is back aboard; the run is won.
signal returned
## Emitted once per run when every player died; the run is lost.
signal lost

enum State { CLOSED, OPEN, RUNNING, STORM, RETURNED, LOST }

const GROUP: StringName = &"missions"

@export var settings: MissionSettings
## The ship players start from and return to; it shows the mission time.
@export var ship: Ship
## The outside world; replaced by a fresh instance of its scene for every mission picked.
@export var location: Node3D

var state: State = State.CLOSED
## The missions on offer at the holo table, from easy to hard.
var offers: Array[MissionBrief] = []
## The picked mission (one of `offers`), or null.
var brief: MissionBrief
## Seconds until the storm hits, 0 afterwards.
var time_left: float
## Seconds since the storm hit.
var storm_time: float = 0.0

## Seconds until the dead respawn when no mission runs (after a lost one, too).
var _respawn_left: float = 0.0
## `duration()` as of the last tick, to notice when it's tuned.
var _duration: float
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)
	_rng.randomize()
	roll_offers()
	time_left = duration()
	_duration = duration()
	_respawn_left = settings.respawn_delay
	ship.mission = self
	# Deferred: the location's nodes build their look in their own _ready (e.g. ore models).
	ship.show_preview.call_deferred(location)
	ship.player_left.connect(_on_player_left)
	ship.ramp_button.used.connect(_on_ramp_button_used)


func _physics_process(delta: float) -> void:
	ship.ramp_button.enabled = _can_start_run()
	_follow_duration()
	match state:
		State.RUNNING:
			time_left = maxf(time_left - delta, 0.0)
			if time_left == 0.0:
				state = State.STORM
				time_up.emit()
		State.STORM:
			storm_time += delta
			_storm_damage(delta)
		_:
			_respawn_after_delay(delta)
			return
	_check_outcome()


## Offers new missions, one per `settings.offers`, running through the difficulties; drops the
## picked one.
func roll_offers() -> void:
	offers.clear()
	brief = null
	for i: int in settings.offers:
		var offer := MissionBrief.new()
		if not settings.biomes.is_empty():
			offer.biome = settings.biomes[_rng.randi() % settings.biomes.size()]
		offer.world_seed = _rng.randi_range(1, 0x7fffffff)
		if not settings.lengths.is_empty():
			offer.length = settings.lengths[_rng.randi() % settings.lengths.size()]
		offer.difficulty = (i % MissionBrief.Difficulty.size()) as MissionBrief.Difficulty
		offers.append(offer)
	offers.sort_custom(
		func(a: MissionBrief, b: MissionBrief) -> bool: return a.difficulty < b.difficulty
	)
	offers_changed.emit()


## Whether a mission can be picked now: not once the ramp is down for one (it's locked then), and
## not while someone is dead.
func can_select() -> bool:
	return state in [State.CLOSED, State.RETURNED, State.LOST] and not _anyone_dead()


## Picks `offer` (one of `offers`): the outside world becomes its location and the timer its
## duration. Returns whether it was picked.
func select(offer: MissionBrief) -> bool:
	if offer not in offers or not can_select():
		return false
	brief = offer
	state = State.CLOSED
	reset_location()
	time_left = duration()
	_duration = duration()
	storm_time = 0.0
	ship.ramp_button.enabled = _can_start_run()
	selected.emit(brief)
	offers_changed.emit()
	return true


## Seconds from the start until the storm hits: the picked mission's length of the standard
## duration.
func duration() -> float:
	return settings.duration * (brief.length if brief else 1.0)


## Replaces the outside world with a fresh instance of its scene (of the picked mission's biome,
## seed and difficulty, if it's generated) and shows it on the holo table.
func reset_location() -> void:
	var parent: Node = location.get_parent()
	var index: int = location.get_index()
	var fresh: Node3D = (load(location.scene_file_path) as PackedScene).instantiate() as Node3D
	var generated := fresh as GeneratedLocation
	if generated and brief:
		generated.biome = brief.biome
		generated.world_seed = brief.world_seed
		generated.nest_factor = settings.nest_factors[brief.difficulty]
	fresh.name = location.name
	fresh.transform = location.transform
	parent.remove_child(location)
	location.queue_free()
	parent.add_child(fresh)
	parent.move_child(fresh, index)
	location = fresh
	ship.show_preview(location)


## Whether a run is underway: someone stepped out and not everyone is back yet.
func is_running() -> bool:
	return state in [State.RUNNING, State.STORM]


## How far the run is: 0 at the start, 1 when the storm hits (and during it). Escalation follows it,
## so it adapts to the mission length.
func progress() -> float:
	match state:
		State.RUNNING:
			return clampf(1.0 - time_left / duration(), 0.0, 1.0)
		State.STORM:
			return 1.0
	return 0.0


## Storm damage per second right now.
func storm_damage_per_second() -> float:
	return settings.storm_damage + settings.storm_damage_growth * storm_time


func _storm_damage(delta: float) -> void:
	var damage: float = storm_damage_per_second() * delta
	for player: Player in _players():
		if not ship.is_aboard(player):
			player.take_damage(damage)


func _check_outcome() -> void:
	var players: Array[Player] = _players()
	if players.is_empty():
		return
	var anyone_alive: bool = false
	for player: Player in players:
		if player.dead:
			continue
		anyone_alive = true
		if not ship.is_aboard(player):
			return
	if anyone_alive:
		_return(players)
	else:
		state = State.LOST
		_respawn_left = settings.respawn_delay
		roll_offers()
		lost.emit()


func _follow_duration() -> void:
	var current: float = duration()
	if current == _duration:
		return
	match state:
		State.CLOSED, State.OPEN:
			time_left = current
		State.RUNNING:
			time_left = maxf(time_left + current - _duration, 0.0)
	_duration = current


## Respawns the dead once they've lain `settings.respawn_delay`; the timer starts with the first
## death. After a lost mission the ramp then goes up.
func _respawn_after_delay(delta: float) -> void:
	if not _anyone_dead():
		_respawn_left = settings.respawn_delay
		return
	_respawn_left = maxf(_respawn_left - delta, 0.0)
	if _respawn_left == 0.0:
		_respawn_dead()
		if state == State.LOST:
			ship.ramp_open = false


func _return(players: Array[Player]) -> void:
	state = State.RETURNED
	ship.ramp_open = false
	for player: Player in players:
		if not player.dead:
			ship.store_cargo(player)
	_respawn_dead()
	roll_offers()
	returned.emit()


func _respawn_dead() -> void:
	for player: Player in _players():
		if player.dead:
			player.respawn(ship.get_respawn_position())


func _can_start_run() -> bool:
	return brief != null and not is_running() and not _anyone_dead()


func _anyone_dead() -> bool:
	for player: Player in _players():
		if player.dead:
			return true
	return false


func _players() -> Array[Player]:
	var players: Array[Player] = []
	players.assign(get_tree().get_nodes_in_group(Player.GROUP))
	return players


func _on_ramp_button_used(_player: Player) -> void:
	if not _can_start_run():
		return
	match state:
		State.CLOSED:
			time_left = duration()
			storm_time = 0.0
			for player: Player in _players():
				player.heal()
			state = State.OPEN
			ship.ramp_open = true
			opened.emit()
		State.OPEN:
			state = State.CLOSED
			ship.ramp_open = false


func _on_player_left(_player: Player) -> void:
	if state == State.OPEN:
		state = State.RUNNING
		started.emit()
