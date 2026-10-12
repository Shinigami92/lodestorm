class_name Mission
extends Node
## The mission loop around the ship. The ramp starts closed; the ramp button inside the ship resets
## the outside world (`location`), resets the timer, heals the players and lowers the ramp (later
## it also locks the selected mission). The mission starts when the first player steps out; the
## timer then counts down from `settings.duration`, and at zero the storm hits (`time_up`) and
## hurts everyone outside, more with every second. Players who die drop what they carried.
## The mission is won (`returned`) once every living player is back aboard, in time or during the
## storm: their cargo goes into the ship's hold, the dead respawn aboard and the ramp goes up.
## It's lost (`lost`) when nobody is left alive; after `settings.respawn_delay` everyone respawns
## aboard. Either way the button then starts the next run. Players who die while no mission runs
## (e.g. killed through the debug overlay) also respawn aboard after `settings.respawn_delay`.
## Changing `settings.duration` while playing (debug overlay) updates the timer: before the start
## it's the new duration, while it runs it moves by the difference.

## Emitted when the ramp button starts a new run: outside world and timer are reset.
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
## The outside world; replaced by a fresh instance of its scene for every run.
@export var location: Node3D

var state: State = State.CLOSED
## Seconds until the storm hits, 0 afterwards.
var time_left: float
## Seconds since the storm hit.
var storm_time: float = 0.0

## Seconds until the dead respawn when no mission runs (after a lost one, too).
var _respawn_left: float = 0.0
## `settings.duration` as of the last tick, to notice when it's tuned.
var _duration: float


func _ready() -> void:
	add_to_group(GROUP)
	time_left = settings.duration
	_duration = settings.duration
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


## Replaces the outside world with a fresh instance of its scene and shows it on the holo table.
func reset_location() -> void:
	var parent: Node = location.get_parent()
	var index: int = location.get_index()
	var fresh: Node3D = (load(location.scene_file_path) as PackedScene).instantiate() as Node3D
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
			return clampf(1.0 - time_left / settings.duration, 0.0, 1.0)
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
		lost.emit()


func _follow_duration() -> void:
	if settings.duration == _duration:
		return
	match state:
		State.CLOSED, State.OPEN:
			time_left = settings.duration
		State.RUNNING:
			time_left = maxf(time_left + settings.duration - _duration, 0.0)
	_duration = settings.duration


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
	returned.emit()


func _respawn_dead() -> void:
	for player: Player in _players():
		if player.dead:
			player.respawn(ship.get_respawn_position())


func _can_start_run() -> bool:
	return not is_running() and not _anyone_dead()


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
		State.CLOSED, State.RETURNED, State.LOST:
			reset_location()
			time_left = settings.duration
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
