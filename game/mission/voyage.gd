class_name Voyage
extends Node
## Where the ship goes. The navigator at the holo table offers a mission per open region of the
## star system (`offers`, `settings.system`; the regions of the bodies the ship's heat shield
## reaches, more once it gets another plate), each a new section of its region (a new seed after
## every run). Showing one at the navigator (`preview`) prepares its location (a fresh instance of
## `location_scene` with the mission's biome and seed, generated on a worker thread) and shows it
## on the holo table; choosing it as the destination (`choose`) is a separate step, and confirming
## that at the cockpit's flight console (`confirm`) sets course: the ship's `flight` takes it there
## (taking off from the current location first; a longer way through space to another planet or
## moon), and the location goes under the ship during the descent. `select` chooses and confirms at
## once. Course can only be set while the `mission` lets the ship leave (no run underway, nobody
## dead) and not in flight.
## A station the ship can dock at (`CelestialBody.is_dockable`) is on offer too, without a mission
## (`MissionBrief.station`): its location is its map (a `SpaceStation`, ready at once), which the
## flight docks at instead of landing; leaving it takes everyone aboard (the ramp goes up by itself
## when course is set), and the ship undocks.
## The game starts in space, or landed at `location` if the map has one (tests); a save made while
## docked docks the ship again (`dock_at`).
## Once a run is over, the mission rolls new offers (`roll_offers`).

## Emitted when the missions on offer, the previewed one or the picked one change.
signal offers_changed
## Emitted when course is set for a mission: the ship flies to its location.
signal selected(brief: MissionBrief)

const GROUP: StringName = &"voyages"
## Name of the outside world's node.
const LOCATION_NAME: StringName = &"Location"

@export var settings: VoyageSettings
## The ship that travels.
@export var ship: Ship
## The run at the location the ship stands at: course can't be set while it's underway.
@export var mission: Mission
## The outside world's scene: every location the ship lands at is a fresh instance of it.
@export var location_scene: PackedScene
## The outside world the ship stands in, null in space. A map that has one starts with the ship
## landed there, and the locations after it stand where it stands; without one, the map starts in
## space, and locations stand where the ship stands (their axes are the ship's).
@export var location: Node3D

## The missions on offer at the holo table, from easy to hard.
var offers: Array[MissionBrief] = []
## The mission shown on the holo table (one of `offers`), or null.
var previewed: MissionBrief
## The mission chosen as the destination at the navigator (one of `offers`), or null: course is
## set for it at the cockpit.
var destination: MissionBrief
## The mission the ship flies to or stands at (one of `offers`), or null.
var brief: MissionBrief
## The planet or moon the ship is at (where it flew last; saved), or null before its first flight
## (see `ship_body`).
var at_body: CelestialBody
## The ship's flight between space and the locations.
var flight: ShipFlight

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
	ship.voyage = self
	roll_offers()
	ship.heat_shield.level_changed.connect(_on_shield_level_changed.unbind(1))
	flight.left_location.connect(_on_left_location)
	flight.reached_location.connect(_on_reached_location)
	_location_transform = ship.transform
	if location:
		_location_transform = location.transform
		flight.land_now()
	# Deferred: the location's nodes build their look in their own _ready (e.g. ore models).
	_show_hologram.call_deferred()


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


## Offers new missions, one per open region of the star system, each with a new seed (a new
## section of its region); drops the previewed and the picked one.
func roll_offers() -> void:
	_discard_prepared()
	offers.clear()
	previewed = null
	destination = null
	brief = null
	offer_open_regions()


## Offers a mission for every open region that has none yet (e.g. once the heat shield got
## another plate), keeping the others, and a visit to every station the ship can dock at.
func offer_open_regions() -> void:
	if settings.system:
		for region: Region in settings.system.open_regions(ship.heat_shield.mk):
			if offer_for(region):
				continue
			var world_seed: int = _rng.randi_range(1, 0x7fffffff)
			var ores: Array[OreType] = settings.system.ores_of(region)
			offers.append(MissionBrief.for_region(region, world_seed, ores))
		for body: CelestialBody in settings.system.bodies:
			if body.is_dockable() and not offer_for_station(body):
				offers.append(MissionBrief.for_station(body))
	offers_changed.emit()


## The planet, moon or station the ship is at: where it flew last, else the first planet or moon
## it can go to (where a new game starts), or null.
func ship_body() -> CelestialBody:
	if at_body or not settings.system:
		return at_body
	for candidate: CelestialBody in settings.system.bodies:
		if (
			candidate.kind != CelestialBody.Kind.STATION
			and candidate.is_reachable(ship.heat_shield.mk)
		):
			return candidate
	return null


## The mission on offer for `region`, or null.
func offer_for(region: Region) -> MissionBrief:
	for offer: MissionBrief in offers:
		if offer.region == region:
			return offer
	return null


## The visit on offer to `station`, or null.
func offer_for_station(station: CelestialBody) -> MissionBrief:
	for offer: MissionBrief in offers:
		if offer.station == station:
			return offer
	return null


## Whether the ship is docked at a station.
func is_docked() -> bool:
	return flight.is_docked()


## Whether a mission can be picked now: not once the ramp is down for one (it's locked then), not
## during the flight, and not while someone is dead (see `Mission.can_leave`).
func can_select() -> bool:
	return mission.can_leave() and not flight.is_flying()


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


## Whether course can be set for the destination now (not for the one the ship is at; docked at
## a station, only with everyone aboard).
func can_confirm() -> bool:
	return (
		can_select()
		and destination != null
		and destination != brief
		and (not is_docked() or ship.everyone_aboard())
	)


## Sets course for the destination: the ship flies to its location (and the mission sets its
## timer, see `selected`); docked at a station, the ramp goes up and the ship undocks first.
## Returns whether it did.
func confirm() -> bool:
	if not can_confirm():
		return false
	brief = destination
	var from_body: CelestialBody = ship_body()
	if brief.station:
		at_body = brief.station
	elif settings.system and brief.region:
		at_body = settings.system.body_of(brief.region)
	_destination_location = _prepared[brief]
	flight.destination_ready = not _tasks.has(brief)
	ship.ramp_open = false
	# Within the same body the ship only takes off and lands; to another one it crosses space.
	flight.fly(at_body if at_body != from_body else null, brief.station != null)
	selected.emit(brief)
	offers_changed.emit()
	return true


## Docks the ship at `station` right away, its map placed around it (a save made while docked).
## Returns whether it did (not in flight, and only at a station on offer).
func dock_at(station: CelestialBody) -> bool:
	var offer: MissionBrief = offer_for_station(station)
	if not offer or flight.is_flying():
		return false
	destination = offer
	brief = offer
	at_body = station
	_prepare(offer)
	if ship.get_parent().is_node_ready():
		_place(_prepared[offer])
	else:
		# Loading a save while the map sets up its nodes: it can't take another child yet.
		_place.call_deferred(_prepared[offer])
	flight.dock_now()
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


## Replaces the outside world right away (no flight) with a fresh one of the picked mission's
## biome, seed and difficulty (tests, debugging).
func reset_location() -> void:
	_place(_instantiate(brief))


## The tier of the body `offer` goes to (see `CelestialBody.tier`), 1 without one (a location of a
## biome anywhere).
func tier_of(offer: MissionBrief) -> int:
	var body: CelestialBody = null
	if offer and offer.region and settings.system:
		body = settings.system.body_of(offer.region)
	return body.tier if body else 1


## A fresh location for `offer` (its biome, seed and difficulty if it's generated; a station's
## map), not built yet.
func _instantiate(offer: MissionBrief) -> Node3D:
	if offer and offer.station:
		var station := offer.station.map.instantiate() as SpaceStation
		station.name = LOCATION_NAME
		station.body = offer.station
		station.flight = flight
		station.viewer = ship.viewer
		return station
	var fresh := location_scene.instantiate() as Node3D
	fresh.name = LOCATION_NAME
	var generated := fresh as GeneratedLocation
	if generated and offer:
		generated.biome = offer.biome
		generated.ores = offer.ores
		generated.world_seed = offer.world_seed
		generated.nest_factor = settings.nest_factor_at(offer.difficulty, tier_of(offer))
		generated.alien_tier = tier_of(offer)
		generated.preview_strain = offer.difficulty == MissionBrief.Difficulty.HARD
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


## Starts preparing `offer`'s location, a generated one on a worker thread (a station's map is
## ready at once).
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
	# A station docks at the ship, wherever the locations stand.
	fresh.transform = ship.transform if fresh is SpaceStation else _location_transform
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


## High above the old location: it's left behind. Without a new course, no mission is picked
## anymore.
func _on_left_location() -> void:
	_remove_location()
	if not _destination_location:
		brief = null
		offers_changed.emit()
	_show_hologram()


## Another plate on the heat shield: the bodies it reaches now offer missions too.
func _on_shield_level_changed() -> void:
	offer_open_regions()


## Under the clouds at the destination: it goes under the ship.
func _on_reached_location() -> void:
	if _destination_location:
		_place(_destination_location)
		_destination_location = null
