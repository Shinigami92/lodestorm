class_name NavigatorStation
extends Station
## The navigator at the bridge's holo table (see docs/design/missions.md, Mission selection). Its
## hologram zooms smoothly (`zoom`, eased towards `zoom_target`) from the star system (0: its
## planets, moons and stations as small holograms around the star) into a planet or moon (1: a globe
## with its regions as bordered areas on the surface) and into a region's landing site (2: the holo
## table's location hologram). Zooming in flies towards the selected body or region: the system
## grows around the body until it becomes the globe, the globe around the region until the landing
## site takes over. `interact` zooms in a whole step (at a landing site: chooses it as the
## destination), `pause`/`ui_cancel` back out a step (and close at the star system);
## `zoom_in`/`zoom_out` (mouse wheel, gamepad triggers, +/-) zoom gradually. A landing site is only
## shown (`Voyage.preview`); choosing it as the destination (`Voyage.choose`, a new section of
## the region) takes "Set as destination" (on the globe, it then zooms into the landing site), and
## course is set at the cockpit's flight console.
## A station the ship can dock at is picked like a region, without a globe: zooming into it (to
## 1) shows its map on the holo table like a landing site (`Voyage.preview`), and "Set as
## destination" (also `interact` there) chooses the visit. A station without a map, the star and
## locked planets and regions can't be zoomed into: zooming stops short of them.
## Its `hologram` (`NavigatorHologram`, the `View` child) builds and places the views; the star's
## name is on the card. The card floats beside the hologram, so it never covers
## a region.
## Players use it from anywhere around the table; walking away leaves the hologram as it is.

enum Level { SYSTEM, BODY, REGION }

## Zoom per mouse wheel step, and per second while a zoom key or trigger is held.
const WHEEL_STEP: float = 0.15
const HOLD_SPEED: float = 1.2
## How fast the shown zoom follows its target (per s).
const ZOOM_SPEED: float = 7.0
## How close zooming gets to what can't be reached (the zoom stops short of the next level).
const UNREACHABLE_LIMIT: float = 0.45
## The landing site's size on the table (of the holo table's own), so the card beside it leaves
## it free.
const LANDING_SCALE: float = 0.8

## Where the card floats, from the hologram's center: right and up on screen, in m.
@export var card_spot: Vector2 = Vector2(2.6, 0.3)
## The table whose location hologram shows the landing site.
@export var holo_table: HoloTable

## The zoom shown and the one it eases towards (0: star system, 1: a body, 2: a landing site).
var zoom: float = 0.0
var zoom_target: float = 0.0
## The body zoomed into (or towards), and the region.
var body: CelestialBody
var region: Region
## Where the ship goes: its offers are shown; found in the scene tree when not set.
var voyage: Voyage
## The level the navigator is at (or zooming to): what its parts are.
var level: Level:
	get:
		return _level_of(zoom_target)

var _site: StationPart
var _parts: Array[StationPart] = []
var _parts_level: Level = Level.SYSTEM

## The system view and the globe (above the table).
@onready var hologram: NavigatorHologram = $View


func _ready() -> void:
	super()
	hologram.navigator = self


func _process(delta: float) -> void:
	super(delta)
	if not voyage:
		voyage = get_tree().get_first_node_in_group(Voyage.GROUP) as Voyage
		if voyage:
			voyage.offers_changed.connect(hologram.build_routes)
			voyage.ship.heat_shield.level_changed.connect(rebuild_hologram.unbind(1))
	if not voyage:
		return
	if not hologram.is_built():
		# The table shows the star system from the start.
		_jump(zoom_target)
	if user:
		var held: float = (
			Input.get_action_strength(&"zoom_in") - Input.get_action_strength(&"zoom_out")
		)
		if absf(held) > 0.01:
			set_zoom_target(zoom_target + held * HOLD_SPEED * delta)
	zoom = lerpf(zoom, zoom_target, 1.0 - exp(-ZOOM_SPEED * delta))
	if absf(zoom - zoom_target) < 0.002:
		zoom = zoom_target
	_keep_landing_site_shown()
	_show_zoom()
	if user:
		refresh()


## The star system shown, or null.
func get_system() -> StarSystem:
	return voyage.settings.system if voyage and voyage.settings else null


func get_parts() -> Array[StationPart]:
	return _parts.duplicate()


## The planet or moon the ship is at: where it flew last, else the first one it can go to.
func ship_body() -> CelestialBody:
	return voyage.ship_body() if voyage else null


## The name plates shown: the system view's (one per body) or the globe's (one per region).
func get_plates() -> Array[HoloPlate]:
	var plates: Array[HoloPlate] = []
	plates.assign(hologram.get_plates(_parts_level == Level.BODY))
	return plates


## The body of the destination chosen (a station to dock at, or a region's planet or moon), or
## null.
func destination_body() -> CelestialBody:
	var system: StarSystem = get_system()
	var destination: MissionBrief = voyage.destination if voyage else null
	if destination and destination.station:
		return destination.station
	return (
		system.body_of(destination.region)
		if system and destination and destination.region
		else null
	)


## Whether `item` is a station the ship docks at (zooming into it shows its map).
static func is_station(item: Resource) -> bool:
	var shown_body := item as CelestialBody
	return shown_body != null and shown_body.is_dockable()


## The ores a plate or card lists for `shown_region` (commonest first): the signature ores of a
## body that can't be reached yet are null ("?").
func shown_ores(shown_region: Region) -> Array[OreType]:
	var system: StarSystem = get_system()
	if not system:
		return []
	var shown_body: CelestialBody = system.body_of(shown_region)
	var ores: Array[OreType] = system.ores_of(shown_region)
	if shown_body and not is_reachable(shown_body):
		for i: int in ores.size():
			if ores[i] in shown_body.signature_ores:
				ores[i] = null
	return ores


## The part showing `item` (a body or a region), or null.
func get_part(item: Resource) -> StationPart:
	for part: StationPart in _parts:
		if part.item == item:
			return part
	return null


## Whether `item` can be zoomed into: a body the ship's heat shield reaches, or one of its regions
## (not the star).
func is_reachable(item: Resource) -> bool:
	var shown_body := item as CelestialBody
	var shown_region := item as Region
	if shown_region and get_system():
		shown_body = get_system().body_of(shown_region)
	return shown_body != null and shown_body.is_reachable(shield_mk())


## The ship's heat shield MK level: how far inwards it can fly.
func shield_mk() -> int:
	var shield: HeatShield = get_heat_shield()
	return shield.mk if shield else 1


## The ship's heat shield, or null.
func get_heat_shield() -> HeatShield:
	return voyage.ship.heat_shield if voyage and voyage.ship else null


## The mission on offer for `item` (a region), the visit to a station, or null.
func get_offer(item: Resource) -> MissionBrief:
	if not voyage:
		return null
	if is_station(item):
		return voyage.offer_for_station(item as CelestialBody)
	var shown_region := item as Region
	return voyage.offer_for(shown_region) if shown_region else null


## Zooms in a whole step: into the selected body, or into the selected region's landing site; at
## a landing site or a station's map, chooses it as the destination. Returns whether it did.
func activate() -> bool:
	if level == Level.REGION or (level == Level.BODY and is_station(body)):
		return choose_destination()
	var before: float = zoom_target
	set_zoom_target(floorf(zoom_target + 0.001) + 1.0)
	return zoom_target > before + 0.5


## Chooses the selected region (or the one whose landing site is shown) or station as the
## destination; on the globe, it then zooms into the region's landing site, at the star system into
## the station's map. Returns whether it is the destination.
func choose_destination() -> bool:
	var picked: Resource = selected.item if selected else null
	if not picked is Region and not is_station(picked):
		return false
	var offer: MissionBrief = get_offer(picked)
	if not offer or not is_reachable(picked):
		return false
	if offer != voyage.destination and not voyage.choose(offer):
		return false
	if is_station(picked):
		if level == Level.SYSTEM:
			body = picked as CelestialBody
			set_zoom_target(1.0)
	elif level == Level.BODY:
		set_zoom_target(2.0)
	return true


## Shows the star system.
func show_system() -> void:
	_jump(0.0)


## Shows `shown_body`'s globe.
func show_body(shown_body: CelestialBody) -> void:
	body = shown_body
	_jump(1.0)


## Shows `shown_region`'s landing site (or its globe, when it's locked). Returns whether it shows
## the landing site.
func show_region(shown_region: Region) -> bool:
	var system: StarSystem = get_system()
	body = system.body_of(shown_region) if system else null
	region = shown_region
	var shown: bool = _show_landing_site()
	_jump(2.0 if shown else 1.0)
	return shown


## Steps back a level (the card's "Back"). Returns whether it did (not at the star system).
func step_back() -> bool:
	return _back()


## Sets where the zoom eases to (zooming towards the selected body or region), stopping short of
## what can't be reached: the star, a station without a map or a locked body, a locked region.
## Reaching a landing site or a station's map shows it (`Voyage.preview`), without choosing it.
func set_zoom_target(value: float) -> void:
	value = clampf(value, 0.0, 2.0)
	var from_level: Level = _level_of(zoom_target)
	if from_level == Level.SYSTEM and value > 0.0:
		if selected:
			body = selected.item as CelestialBody
		if not body or not is_reachable(body):
			value = minf(value, UNREACHABLE_LIMIT)
		elif is_station(body):
			# Its map crossfades in on the way.
			value = minf(value, 1.0)
			if not _show_station_map():
				value = minf(value, UNREACHABLE_LIMIT)
		else:
			hologram.globe_parts(body)
	if is_station(body) and value > 1.0:
		value = 1.0
	if from_level == Level.BODY and value > 1.0:
		var towards := selected.item as Region if selected else null
		if towards:
			region = towards
		if value >= 2.0 - 0.001 and not _show_landing_site():
			value = minf(value, 1.0 + UNREACHABLE_LIMIT)
		elif not region or not is_reachable(region):
			value = minf(value, 1.0 + UNREACHABLE_LIMIT)
	zoom_target = value
	var to_level: Level = _level_of(value)
	if to_level != _parts_level:
		_rebuild(to_level)


func _back() -> bool:
	if zoom_target <= 0.001:
		return false
	set_zoom_target(ceilf(zoom_target - 0.001) - 1.0)
	return true


func _shortcut(event: InputEvent) -> bool:
	var wheel := event as InputEventMouseButton
	if not wheel or not wheel.pressed:
		return false
	if event.is_action_pressed(&"zoom_in"):
		_aim_at_cursor(wheel.position)
		set_zoom_target(zoom_target + WHEEL_STEP)
		return true
	if event.is_action_pressed(&"zoom_out"):
		set_zoom_target(zoom_target - WHEEL_STEP)
		return true
	return false


func _opened() -> void:
	# Carries on where it was left.
	_rebuild(level)
	super()


func _part_at(camera: Camera3D, screen_position: Vector2) -> StationPart:
	if _parts_level != Level.BODY:
		return super(camera, screen_position)
	return hologram.globe_part_at(camera, screen_position)


func _card_position(camera: Camera3D) -> Vector3:
	var view: Basis = camera.global_basis
	return hologram.global_position + view.x * card_spot.x + view.y * card_spot.y


## Builds the hologram again (e.g. once the heat shield got another plate: it shows what can be
## reached), keeping what it shows.
func rebuild_hologram() -> void:
	if not hologram or not hologram.is_built():
		# Not shown yet: it's built with what can be reached when it first is.
		return
	hologram.clear()
	_jump(zoom_target)


## Jumps to `value` without easing (opening, showing a body or region directly).
func _jump(value: float) -> void:
	zoom_target = value
	zoom = value
	_rebuild(_level_of(value))
	_show_zoom()


## Shows the region's landing site on the holo table (just looking). Returns whether it does.
func _show_landing_site() -> bool:
	if not region or not is_reachable(region):
		return false
	var offer: MissionBrief = get_offer(region)
	return offer != null and (offer == voyage.previewed or voyage.preview(offer))


## Shows the station zoomed into's map on the holo table (just looking). Returns whether it does.
func _show_station_map() -> bool:
	var offer: MissionBrief = get_offer(body)
	return offer != null and (offer == voyage.previewed or voyage.preview(offer))


## At a landing site, keeps showing it (after a run, its region offers a new section); the same at
## a station's map.
func _keep_landing_site_shown() -> void:
	if level == Level.REGION and region and get_offer(region) != voyage.previewed:
		_show_landing_site()
	elif level == Level.BODY and is_station(body) and get_offer(body) != voyage.previewed:
		_show_station_map()


## Selects the part under the mouse cursor before the wheel zooms into it.
func _aim_at_cursor(screen_position: Vector2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return
	var part: StationPart = _part_at(camera, screen_position)
	if part:
		select(part)


static func _level_of(value: float) -> Level:
	if value >= 2.0 - 0.001:
		return Level.REGION
	if value >= 1.0 - 0.001:
		return Level.BODY
	return Level.SYSTEM


## Rebuilds the parts for `new_level` and selects what it zoomed out of or into (the body at the
## star system, the region on the globe), else the first part.
func _rebuild(new_level: Level) -> void:
	_parts_level = new_level
	if hovered:
		_hover(null)
	if _site:
		_site.queue_free()
		_site = null
	_parts.clear()
	var focus: Resource = null
	match new_level:
		Level.SYSTEM:
			_parts = hologram.system_parts()
			focus = body
		Level.BODY:
			if is_station(body):
				# The station's map on the holo table: one part, like a landing site.
				_site = StationPart.new()
				_site.item = body
				_site.pick_radius = 0.4
				hologram.add_child(_site)
				_parts.append(_site)
			else:
				_parts = hologram.globe_parts(body)
				focus = region
		Level.REGION:
			_site = StationPart.new()
			_site.item = region
			_site.pick_radius = 0.4
			hologram.add_child(_site)
			_parts.append(_site)
	if user:
		var focused: StationPart = get_part(focus) if focus else null
		select(focused if focused else (_parts[0] if not _parts.is_empty() else null))


## Places the views for `zoom` (see `NavigatorHologram.show_zoom`), and the landing site on the
## holo table once the zoom reaches it.
func _show_zoom() -> void:
	hologram.show_zoom(zoom, body, region)
	if holo_table:
		var stage: float = clampf(zoom, 0.0, 2.0)
		var site: float = NavigatorHologram.crossfade(stage - 1.0) if stage >= 1.0 else 0.0
		if is_station(body):
			# A station's map takes over from the star system right away.
			site = NavigatorHologram.crossfade(stage) if stage < 1.0 else 1.0
		holo_table.show_hologram(site > 0.0)
		holo_table.set_hologram_scale(lerpf(0.3, 1.0, site) * LANDING_SCALE)
