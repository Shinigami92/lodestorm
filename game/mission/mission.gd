class_name Mission
extends Node
## The run at the location the ship stands at (see `Voyage` for getting there). Setting course
## (`Voyage.selected`) resets the timer (`duration`). The ramp starts closed; the ramp button inside
## the ship only works with a mission picked and the ship landed there: it resets the timer,
## refills the players' ammo (their health carries over: the med beds heal), lowers the ramp and
## locks the mission. The mission starts when the first player steps out; the timer then counts
## down, and at zero the storm hits (`time_up`) and hurts everyone outside, more with every second.
## Players who die drop what they carried. Bodies farther in (a higher `tier`) have more and
## stronger aliens, an earlier warning and a harsher storm.
## The mission is won (`returned`) once every living player is back aboard, in time or during the
## storm: their cargo is the haul (see `Ship.store_haul`), the dead respawn aboard and the ramp
## goes up.
## It's lost (`lost`) when nobody is left alive; after `settings.respawn_delay` everyone respawns
## aboard. Either way the mission is done: the voyage offers new ones, and once the ramp is up the
## ship takes off into space after the flight's `takeoff_delay`, unless a new course is set before.
## Either way, crafted miners still standing on the planet are lost there (`MinerFleet.end_run`).
## Players who die while no mission runs (e.g. killed through the debug overlay) also respawn
## aboard after `settings.respawn_delay`.
## Docked at a station there's no run: the ramp button lowers and raises the ramp freely.
## Changing `settings.duration` while playing (debug overlay) updates the timer: before the start
## it's the new duration, while it runs it moves by the difference.

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
## Where the ship goes: the mission picked there is the one run here.
@export var voyage: Voyage

var state: State = State.CLOSED
## Seconds until the storm hits, 0 afterwards.
var time_left: float
## Seconds since the storm hit.
var storm_time: float = 0.0

## Seconds until the dead respawn when no mission runs (after a lost one, too).
var _respawn_left: float = 0.0
## Seconds until the ship takes off after a run.
var _takeoff_left: float = 0.0
## `duration()` as of the last tick, to notice when it's tuned.
var _duration: float


func _ready() -> void:
	add_to_group(GROUP)
	time_left = duration()
	_duration = duration()
	_respawn_left = settings.respawn_delay
	_takeoff_left = ship.flight.settings.takeoff_delay
	ship.mission = self
	voyage.selected.connect(_on_selected.unbind(1))
	ship.flight.left_location.connect(_on_left_location)
	ship.flight.landed.connect(_on_landed)
	ship.flight.docked.connect(_on_landed)
	ship.player_left.connect(_on_player_left)
	ship.ramp_button.used.connect(_on_ramp_button_used)


func _physics_process(delta: float) -> void:
	ship.ramp_button.enabled = _can_start_run() or ship.flight.is_docked()
	_follow_duration()
	match state:
		State.RUNNING:
			var before: float = time_left
			time_left = maxf(time_left - delta, 0.0)
			if before > warning_time() and time_left <= warning_time():
				GameEvents.bus.storm_warned.emit()
			if time_left == 0.0:
				state = State.STORM
				time_up.emit()
				GameEvents.bus.storm_started.emit()
		State.STORM:
			storm_time += delta
			_storm_damage(delta)
		_:
			_respawn_after_delay(delta)
			_take_off_after_delay(delta)
			return
	_check_outcome()


## Whether the ship may leave for another location: no run underway (from the ramp button until
## it's won or lost) and nobody dead.
func can_leave() -> bool:
	return state in [State.CLOSED, State.RETURNED, State.LOST] and not _anyone_dead()


## Seconds from the start until the storm hits: the picked mission's length of the standard
## duration.
func duration() -> float:
	return settings.duration * (voyage.brief.length if voyage.brief else 1.0)


## Whether a run is underway: someone stepped out and not everyone is back yet.
func is_running() -> bool:
	return state in [State.RUNNING, State.STORM]


## Whether the ramp is down for a run, from the button until the run is won or lost. Meanwhile
## loadouts are locked.
func is_underway() -> bool:
	return state in [State.OPEN, State.RUNNING, State.STORM]


## How far the run is: 0 at the start, 1 when the storm hits (and during it). Escalation follows it,
## so it adapts to the mission length.
func progress() -> float:
	match state:
		State.RUNNING:
			return clampf(1.0 - time_left / duration(), 0.0, 1.0)
		State.STORM:
			return 1.0
	return 0.0


## Storm damage per second right now: its growth rises with the tier.
func storm_damage_per_second() -> float:
	return settings.storm_damage + settings.storm_growth_at(tier()) * storm_time


## The tier of the body the ship flies to or stands at (see `CelestialBody.tier`), 1 without one.
func tier() -> int:
	return voyage.tier_of(voyage.brief)


## Seconds before the storm when the warning starts: earlier with the tier.
func warning_time() -> float:
	return settings.warning_time_at(tier())


## Whether the storm's warning is on: the run's last `warning_time` seconds.
func is_warning() -> bool:
	return state == State.RUNNING and time_left <= warning_time()


## Takes what the living among `players` carry into the hold as a haul (see `Ship.store_haul`),
## run or not; the run goes on.
func bank(players: Array[Player]) -> void:
	var haul: Dictionary[OreType, float] = {}
	for player: Player in players:
		if player.dead:
			continue
		var cargo: Dictionary[OreType, float] = player.cargo.take_all()
		_count_hauled(player, cargo)
		for ore_type: OreType in cargo:
			var so_far: float = haul.get(ore_type, 0.0)
			haul[ore_type] = so_far + cargo[ore_type]
	ship.store_haul(haul, _players())


## Takes `haul`, taken out of `player`'s cargo (e.g. at the cargo hatch), into the hold the same way
## (see `Ship.store_haul`); the run goes on.
func bank_ore(player: Player, haul: Dictionary[OreType, float]) -> void:
	_count_hauled(player, haul)
	ship.store_haul(haul, _players())


func _count_hauled(player: Player, haul: Dictionary[OreType, float]) -> void:
	for ore_type: OreType in haul:
		GameEvents.bus.ore_hauled.emit(player, ore_type, haul[ore_type])


func _storm_damage(delta: float) -> void:
	var damage: float = storm_damage_per_second() * delta
	for player: Player in _players():
		if not ship.is_aboard(player):
			player.take_damage(damage, Vector3.INF, null, false, self)


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
		_leave_miners(players)
		_respawn_left = settings.respawn_delay
		_takeoff_left = ship.flight.settings.takeoff_delay
		var ended: MissionBrief = voyage.brief
		voyage.roll_offers()
		lost.emit()
		GameEvents.bus.mission_ended.emit(ended, false)


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


## After a run, once everyone is alive and aboard and the ramp is up, the ship takes off after the
## flight's `takeoff_delay`.
func _take_off_after_delay(delta: float) -> void:
	if (
		state not in [State.RETURNED, State.LOST]
		or ship.flight.phase != ShipFlight.Phase.LANDED
		or not ship.is_ramp_up()
		or _anyone_dead()
	):
		_takeoff_left = ship.flight.settings.takeoff_delay
		return
	_takeoff_left = maxf(_takeoff_left - delta, 0.0)
	if _takeoff_left == 0.0:
		ship.flight.take_off()


func _return(players: Array[Player]) -> void:
	state = State.RETURNED
	ship.ramp_open = false
	bank(players)
	_leave_miners(players)
	_respawn_dead()
	_takeoff_left = ship.flight.settings.takeoff_delay
	var ended: MissionBrief = voyage.brief
	voyage.roll_offers()
	returned.emit()
	GameEvents.bus.mission_ended.emit(ended, true)


## Ends the run for every player's miners: crafted ones still on the planet are lost there (see
## `MinerFleet.end_run`).
func _leave_miners(players: Array[Player]) -> void:
	var brief: MissionBrief = voyage.brief
	var where: String = brief.place_name(voyage.settings.system) if brief else ""
	for player: Player in players:
		player.fleet.end_run(where)


func _respawn_dead() -> void:
	for player: Player in _players():
		if player.dead:
			player.respawn(ship.get_respawn_position())


func _can_start_run() -> bool:
	return (
		voyage.brief != null
		and not is_running()
		and not _anyone_dead()
		and ship.flight.phase == ShipFlight.Phase.LANDED
		and voyage.location != null
	)


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
	if ship.flight.is_docked():
		ship.ramp_open = not ship.ramp_open
		return
	if not _can_start_run():
		return
	match state:
		State.CLOSED:
			time_left = duration()
			storm_time = 0.0
			for player: Player in _players():
				player.refill_ammo()
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
		GameEvents.bus.mission_started.emit(voyage.brief)


func _on_landed() -> void:
	ship.ramp_button.enabled = _can_start_run() or ship.flight.is_docked()


## Course is set for a new mission: its timer, and no run there yet.
func _on_selected() -> void:
	state = State.CLOSED
	time_left = duration()
	_duration = duration()
	storm_time = 0.0
	ship.ramp_button.enabled = _can_start_run() or ship.flight.is_docked()


## High above the old location: the run that was there is over.
func _on_left_location() -> void:
	if state in [State.RETURNED, State.LOST]:
		state = State.CLOSED
