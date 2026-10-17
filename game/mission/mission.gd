class_name Mission
extends Node
## The mission loop around the ship. The navigator at the holo table offers a mission per open
## region of the star system (`offers`, `settings.system`), each a new section of its region (a
## new seed after every run). Showing one at the navigator (`preview`) prepares its location (a
## fresh instance of `location_scene` with the mission's biome and seed, generated on a worker
## thread) and shows it on the holo table; choosing it as the destination (`choose`) is a separate
## step, and confirming that at the cockpit's flight console (`confirm`) sets course and the timer
## (`duration`): the ship's `flight` takes it there (taking off from the current location first),
## and the location goes under the ship during the descent. `select` chooses and confirms at once.
## The game starts in space, or landed at `location` if the map has one (tests).
## The ramp starts closed; the ramp button inside the ship only works with a mission picked and
## the ship landed there: it resets the timer, heals the players, lowers the ramp and locks the
## mission. The mission starts when the first player steps out; the timer then counts down, and at
## zero the storm hits (`time_up`) and hurts everyone outside, more with every second. Players who
## die drop what they carried.
## The mission is won (`returned`) once every living player is back aboard, in time or during the
## storm: their cargo goes into the ship's hold, the dead respawn aboard and the ramp goes up.
## It's lost (`lost`) when nobody is left alive; after `settings.respawn_delay` everyone respawns
## aboard. Either way the mission is done: new ones are offered, and once the ramp is up the ship
## takes off into space after the flight's `takeoff_delay`, unless a new course is set before.
## Players who die while no mission runs (e.g. killed through the debug overlay) also respawn
## aboard after `settings.respawn_delay`.
## Changing `settings.duration` while playing (debug overlay) updates the timer: before the start
## it's the new duration, while it runs it moves by the difference.

## Emitted when the missions on offer, the previewed one or the picked one change.
signal offers_changed
## Emitted when course is set for a mission: the ship flies to its location.
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
## Name of the outside world's node.
const LOCATION_NAME: StringName = &"Location"

@export var settings: MissionSettings
## The ship players start from and return to; it shows the mission time.
@export var ship: Ship
## The outside world's scene: every location the ship lands at is a fresh instance of it.
@export var location_scene: PackedScene
## The outside world the ship stands in, null in space. A map that has one starts with the ship
## landed there, and the locations after it stand where it stands; without one, the map starts in
## space, and locations stand where the ship stands (their axes are the ship's).
@export var location: Node3D

var state: State = State.CLOSED
## The missions on offer at the holo table, from easy to hard.
var offers: Array[MissionBrief] = []
## The mission shown on the holo table (one of `offers`), or null.
var previewed: MissionBrief
## The mission chosen as the destination at the navigator (one of `offers`), or null: course is
## set for it at the cockpit.
var destination: MissionBrief
## The mission the ship flies to or stands at (one of `offers`), or null.
var brief: MissionBrief
## Seconds until the storm hits, 0 afterwards.
var time_left: float
## Seconds since the storm hit.
var storm_time: float = 0.0
## The ship's flight between space and the locations.
var flight: ShipFlight

## Seconds until the dead respawn when no mission runs (after a lost one, too).
var _respawn_left: float = 0.0
## Seconds until the ship takes off after a run.
var _takeoff_left: float = 0.0
## `duration()` as of the last tick, to notice when it's tuned.
var _duration: float
var _rng := RandomNumberGenerator.new()
## Locations prepared for offers; outside the tree until the ship lands at one.
var _prepared: Dictionary[MissionBrief, Node3D] = {}
## Worker thread tasks still planning prepared locations.
var _tasks: Dictionary[MissionBrief, int] = {}
## Prepared locations nobody needs anymore whose planning still runs, by task; freed once done.
var _discarded: Dictionary[int, Node3D] = {}
## The location the flight goes to, until it's placed under the ship.
var _destination_location: Node3D
## Where locations stand, relative to the ship's parent.
var _location_transform: Transform3D


func _ready() -> void:
	add_to_group(GROUP)
	_rng.randomize()
	flight = ship.flight
	roll_offers()
	time_left = duration()
	_duration = duration()
	_respawn_left = settings.respawn_delay
	_takeoff_left = flight.settings.takeoff_delay
	ship.mission = self
	flight.left_location.connect(_on_left_location)
	flight.reached_location.connect(_on_reached_location)
	flight.landed.connect(_on_landed)
	_location_transform = ship.transform
	if location:
		_location_transform = location.transform
		flight.land_now()
	# Deferred: the location's nodes build their look in their own _ready (e.g. ore models).
	_show_hologram.call_deferred()
	ship.player_left.connect(_on_player_left)
	ship.ramp_button.used.connect(_on_ramp_button_used)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_prepared()


func _process(_delta: float) -> void:
	for offer: MissionBrief in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[offer]):
			_finish_preparing(offer)
	for task: int in _discarded.keys():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_discarded[task].free()
			_discarded.erase(task)


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
			_take_off_after_delay(delta)
			return
	_check_outcome()


## Offers new missions, one per open region of the star system, each with a new seed (a new
## section of its region); drops the previewed and the picked one.
func roll_offers() -> void:
	_discard_prepared()
	offers.clear()
	previewed = null
	destination = null
	brief = null
	offer_open_regions()


## Offers a mission for every open region that has none yet (e.g. once regions were unlocked),
## keeping the others.
func offer_open_regions() -> void:
	if settings.system:
		for region: Region in settings.system.open_regions():
			if offer_for(region):
				continue
			var world_seed: int = _rng.randi_range(1, 0x7fffffff)
			var ores: Array[OreType] = settings.system.ores_of(region)
			offers.append(MissionBrief.for_region(region, world_seed, ores))
	offers_changed.emit()


## The mission on offer for `region`, or null.
func offer_for(region: Region) -> MissionBrief:
	for offer: MissionBrief in offers:
		if offer.region == region:
			return offer
	return null


## Whether a mission can be picked now: not once the ramp is down for one (it's locked then), not
## during the flight, and not while someone is dead.
func can_select() -> bool:
	return (
		state in [State.CLOSED, State.RETURNED, State.LOST]
		and not flight.is_flying()
		and not _anyone_dead()
	)


## Shows `offer` (one of `offers`) on the holo table, preparing its location first if needed (just
## looking: it doesn't choose it). Returns whether it's shown.
func preview(offer: MissionBrief) -> bool:
	if offer not in offers:
		return false
	previewed = offer
	_prepare(offer)
	_show_hologram()
	offers_changed.emit()
	return true


## Chooses `offer` (one of `offers`) as the destination, preparing its location if needed. Not
## once the ramp is down, in flight or while someone is dead (see `can_select`). Returns whether
## it did.
func choose(offer: MissionBrief) -> bool:
	if offer not in offers or not can_select():
		return false
	destination = offer
	_prepare(offer)
	offers_changed.emit()
	return true


## Whether `offer`'s location is still being prepared (the hologram shows it once it's ready).
func is_preparing(offer: MissionBrief) -> bool:
	return offer != null and _tasks.has(offer)


## Whether course can be set for the destination now (not for the one the ship is at).
func can_confirm() -> bool:
	return can_select() and destination != null and destination != brief


## Sets course for the destination: its timer, and the ship flies to its location. Returns whether
## it did.
func confirm() -> bool:
	if not can_confirm():
		return false
	brief = destination
	state = State.CLOSED
	time_left = duration()
	_duration = duration()
	storm_time = 0.0
	_destination_location = _prepared[brief]
	flight.destination_ready = not _tasks.has(brief)
	flight.fly()
	ship.ramp_button.enabled = _can_start_run()
	selected.emit(brief)
	offers_changed.emit()
	return true


## Chooses `offer` and sets course for it (tests, debugging). Returns whether it did.
func select(offer: MissionBrief) -> bool:
	return choose(offer) and confirm()


## Finishes the flight at once (debug overlay, tests), waiting for the location to be prepared.
func skip_flight() -> void:
	if brief and _tasks.has(brief):
		_finish_preparing(brief)
	flight.skip()


## Seconds from the start until the storm hits: the picked mission's length of the standard
## duration.
func duration() -> float:
	return settings.duration * (brief.length if brief else 1.0)


## Replaces the outside world right away (no flight) with a fresh one of the picked mission's
## biome, seed and difficulty (tests, debugging).
func reset_location() -> void:
	_place(_instantiate(brief))


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


## Storm damage per second right now.
func storm_damage_per_second() -> float:
	return settings.storm_damage + settings.storm_damage_growth * storm_time


## A fresh location for `offer` (its biome, seed and difficulty if it's generated), not built yet.
func _instantiate(offer: MissionBrief) -> Node3D:
	var fresh := location_scene.instantiate() as Node3D
	fresh.name = LOCATION_NAME
	var generated := fresh as GeneratedLocation
	if generated and offer:
		generated.biome = offer.biome
		generated.ores = offer.ores
		generated.world_seed = offer.world_seed
		generated.nest_factor = settings.nest_factors[offer.difficulty]
		generated.area_count = maxi(roundi(settings.location_areas * offer.length), 4)
		if offer.region:
			generated.set_pieces = offer.region.set_pieces
		var rig := get_tree().get_first_node_in_group(IsoCameraRig.GROUP) as IsoCameraRig
		if rig:
			# Where the camera looks, seen from the location (it stands where the ship lands).
			var parent := ship.get_parent() as Node3D
			var location_basis: Basis = parent.global_basis * _location_transform.basis
			generated.view_direction = location_basis.inverse() * rig.view_direction()
	return fresh


## Starts preparing `offer`'s location, a generated one on a worker thread.
func _prepare(offer: MissionBrief) -> void:
	if _prepared.has(offer):
		return
	var fresh: Node3D = _instantiate(offer)
	_prepared[offer] = fresh
	var generated := fresh as GeneratedLocation
	if generated:
		_tasks[offer] = WorkerThreadPool.add_task(generated.plan, false, "Plan location")


## Waits for `offer`'s location to be planned and builds it.
func _finish_preparing(offer: MissionBrief) -> void:
	if _tasks.has(offer):
		WorkerThreadPool.wait_for_task_completion(_tasks[offer])
		_tasks.erase(offer)
	var prepared: Node3D = _prepared[offer]
	var generated := prepared as GeneratedLocation
	if generated:
		generated.build()
	if prepared == _destination_location:
		flight.destination_ready = true
	if offer == previewed:
		_show_hologram()


## Drops the prepared locations except the one the ship flies to.
func _discard_prepared() -> void:
	for offer: MissionBrief in _prepared.keys():
		var prepared: Node3D = _prepared[offer]
		if prepared == _destination_location:
			continue
		if _tasks.has(offer):
			_discarded[_tasks[offer]] = prepared
			_tasks.erase(offer)
		else:
			prepared.free()
		_prepared.erase(offer)


## Frees every location outside the tree once its planning is done.
func _free_prepared() -> void:
	for task: int in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(task)
	for task: int in _discarded:
		WorkerThreadPool.wait_for_task_completion(task)
	var orphans: Array[Node3D] = []
	orphans.assign(_prepared.values() + _discarded.values())
	for orphan: Node3D in orphans:
		if is_instance_valid(orphan) and not orphan.is_inside_tree():
			orphan.free()
	_prepared.clear()
	_tasks.clear()
	_discarded.clear()


## The location shown on the holo table: the previewed mission's once it's prepared, otherwise the
## one the ship stands in.
func _show_hologram() -> void:
	var shown: Node3D = location
	if previewed:
		shown = null
		if _prepared.has(previewed):
			if not _tasks.has(previewed):
				shown = _prepared[previewed]
		elif previewed == brief:
			shown = location
	ship.show_preview(shown)


## Puts `fresh` under the ship as the outside world, replacing the old one.
func _place(fresh: Node3D) -> void:
	_remove_location()
	for offer: MissionBrief in _prepared.keys():
		if _prepared[offer] == fresh:
			_prepared.erase(offer)
	var parent: Node = ship.get_parent()
	fresh.transform = _location_transform
	parent.add_child(fresh)
	parent.move_child(fresh, ship.get_index())
	location = fresh
	_show_hologram()


func _remove_location() -> void:
	if not location:
		return
	location.get_parent().remove_child(location)
	location.queue_free()
	location = null


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
		_takeoff_left = flight.settings.takeoff_delay
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


## After a run, once everyone is alive and aboard and the ramp is up, the ship takes off after the
## flight's `takeoff_delay`.
func _take_off_after_delay(delta: float) -> void:
	if (
		state not in [State.RETURNED, State.LOST]
		or flight.phase != ShipFlight.Phase.LANDED
		or not ship.is_ramp_up()
		or _anyone_dead()
	):
		_takeoff_left = flight.settings.takeoff_delay
		return
	_takeoff_left = maxf(_takeoff_left - delta, 0.0)
	if _takeoff_left == 0.0:
		flight.take_off()


func _return(players: Array[Player]) -> void:
	state = State.RETURNED
	ship.ramp_open = false
	for player: Player in players:
		if not player.dead:
			ship.store_cargo(player)
	_respawn_dead()
	_takeoff_left = flight.settings.takeoff_delay
	roll_offers()
	returned.emit()


func _respawn_dead() -> void:
	for player: Player in _players():
		if player.dead:
			player.respawn(ship.get_respawn_position())


func _can_start_run() -> bool:
	return (
		brief != null
		and not is_running()
		and not _anyone_dead()
		and flight.phase == ShipFlight.Phase.LANDED
		and location != null
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
	if not _can_start_run():
		return
	match state:
		State.CLOSED:
			time_left = duration()
			storm_time = 0.0
			for player: Player in _players():
				player.heal()
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


## High above the old location: it's left behind, and the run that was there is over. Without a
## new course, no mission is picked anymore.
func _on_left_location() -> void:
	_remove_location()
	if state in [State.RETURNED, State.LOST]:
		state = State.CLOSED
	if not _destination_location:
		brief = null
		offers_changed.emit()
	_show_hologram()


func _on_landed() -> void:
	ship.ramp_button.enabled = _can_start_run()


## Under the clouds at the destination: it goes under the ship.
func _on_reached_location() -> void:
	if _destination_location:
		_place(_destination_location)
		_destination_location = null
