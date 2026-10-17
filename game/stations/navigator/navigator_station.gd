class_name NavigatorStation
extends Station
## The navigator at the bridge's holo table (see GAME_DESIGN.md, Mission selection). Its hologram
## zooms smoothly (`zoom`, eased towards `zoom_target`) from the star system (0: its planets, moons
## and stations as small holograms around the star) into a planet or moon (1: a globe with its
## regions as bordered areas on the surface) and into a region's landing site (2: the holo table's
## location hologram). Zooming in flies towards the selected body or region: the system grows
## around the body until it becomes the globe, the globe around the region until the landing site
## takes over. `interact` zooms in a whole step (at a landing site: chooses it as the
## destination), `pause`/`ui_cancel` back out a step (and close at the star system);
## `zoom_in`/`zoom_out` (mouse wheel, gamepad triggers, +/-) zoom gradually. A landing site is only
## shown (`Mission.preview`); choosing it as the destination (`Mission.choose`, a new section of
## the region) takes "Set as destination", and course is set at the cockpit's flight console.
## Stations can't be docked at yet and locked planets and regions can't be visited: zooming stops
## short of them. The star system shows orbit lines (spread evenly, so every body fits on the
## table), the star (with its name on the card), stations as station shapes, a name plate per body
## with its signature ore ("?" while out of reach), the ship's marker and routes to where it can
## go. A globe fills its regions in their biome's color, with a plate per region (name, danger
## pips, ores). The card floats beside the hologram, so it never covers a region.
## Players use it from anywhere around the table; walking away leaves the hologram as it is.

enum Level { SYSTEM, BODY, REGION }

## How see-through what can't be reached is.
const UNREACHABLE_FADE: float = 0.35
## Zoom per mouse wheel step, and per second while a zoom key or trigger is held.
const WHEEL_STEP: float = 0.15
const HOLD_SPEED: float = 1.2
## How fast the shown zoom follows its target (per s).
const ZOOM_SPEED: float = 7.0
## How close zooming gets to what can't be reached (the zoom stops short of the next level).
const UNREACHABLE_LIMIT: float = 0.45
## How much the globe grows while zooming into a region, and where (of each step) the next view
## starts fading in.
const REGION_ZOOM: float = 4.0
const CROSSFADE_FROM: float = 0.75
const HOLOGRAM_ENERGY: float = 0.9
## The landing site's size on the table (of the holo table's own), so the card beside it leaves
## it free.
const LANDING_SCALE: float = 0.8
const ORBIT_COLOR := Color(0.3, 0.85, 1.0)
## The ship's marker and the route to the destination; the routes to the other reachable bodies.
const SHIP_COLOR := Color(1.0, 0.72, 0.3)
const ROUTE_COLOR := Color(0.3, 0.85, 1.0)
## Distance between a route's dots, in m, and how high a route arcs (of its length).
const ROUTE_STEP: float = 0.045
const ROUTE_ARC: float = 0.22
## How far a plate on the globe faces the camera at least to show (cosine), and fully.
const PLATE_FACING_FROM: float = 0.15
const PLATE_FACING_FULL: float = 0.45

## The system view's size, so every body fits on the table: the innermost and the outermost orbit
## around the star (in m; the ones in between spread evenly, in the order of their
## `orbit_radius`), how far apart the moons' orbits around a planet's surface are, and the size
## (in m) of a body of `size` 1.
@export var inner_orbit: float = 0.4
@export var outer_orbit: float = 1.25
@export var moon_orbit: float = 0.1
@export var body_scale: float = 0.24
## The globe's radius in m, and how far a region reaches on it from its center (degrees).
@export var globe_radius: float = 0.9
@export var region_reach: float = 35.0
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
## The mission whose offers it shows; found in the scene tree when not set.
var mission: Mission
## The level the navigator is at (or zooming to): what its parts are.
var level: Level:
	get:
		return _level_of(zoom_target)

var _site: StationPart
var _parts: Array[StationPart] = []
var _parts_level: Level = Level.SYSTEM
var _system: Node3D
var _globe: Node3D
var _globe_material: ShaderMaterial
var _body_parts: Dictionary[CelestialBody, StationPart] = {}
## Every hologram material of the system view and its energy at full view (they fade together).
var _system_materials: Dictionary[ShaderMaterial, float] = {}
## The system view's name plates and how visible each is at full view.
var _system_plates: Dictionary[HoloPlate, float] = {}
## The ship's marker and the routes (rebuilt when the destination changes).
var _routes: Node3D
var _route_materials: Dictionary[Color, ShaderMaterial] = {}
## The globe's region plates and where each region's center lies on it.
var _region_plates: Dictionary[HoloPlate, Vector3] = {}

## Where the system view and the globe are built (above the table).
@onready var _view: Node3D = $View


func _process(delta: float) -> void:
	super(delta)
	if not mission:
		mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
		if mission:
			mission.offers_changed.connect(_build_routes)
	if not mission:
		return
	if not _system:
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
	return mission.settings.system if mission and mission.settings else null


func get_parts() -> Array[StationPart]:
	return _parts.duplicate()


## How far `shown_body`'s orbit lies from what it orbits in the system view, in m: the star's
## orbits spread evenly from `inner_orbit` to `outer_orbit` in the order of their `orbit_radius`,
## a planet's moons one `moon_orbit` after another outside its surface.
func display_orbit(shown_body: CelestialBody) -> float:
	var system: StarSystem = get_system()
	if not system:
		return 0.0
	var siblings: Array[CelestialBody] = []
	for other: CelestialBody in system.bodies:
		if other.orbits == shown_body.orbits:
			siblings.append(other)
	siblings.sort_custom(
		func(a: CelestialBody, b: CelestialBody) -> bool: return a.orbit_radius < b.orbit_radius
	)
	var index: int = siblings.find(shown_body)
	if shown_body.orbits:
		return shown_body.orbits.size * body_scale * 0.5 + moon_orbit * (index + 1)
	if siblings.size() < 2:
		return outer_orbit
	return lerpf(inner_orbit, outer_orbit, float(index) / (siblings.size() - 1))


## The planet or moon the ship is at: where it flew last, else the first one it can go to.
func ship_body() -> CelestialBody:
	if mission and mission.at_body:
		return mission.at_body
	var system: StarSystem = get_system()
	if system:
		for candidate: CelestialBody in system.bodies:
			if candidate.kind != CelestialBody.Kind.STATION and candidate.is_reachable():
				return candidate
	return null


## The name plates shown: the system view's (one per body) or the globe's (one per region).
func get_plates() -> Array[HoloPlate]:
	var plates: Array[HoloPlate] = []
	plates.assign(_region_plates.keys() if _parts_level == Level.BODY else _system_plates.keys())
	return plates


## The routes drawn: `{body: the body a route goes to, chosen: whether it's the destination's}`.
func get_routes() -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	if _routes:
		for child: Node in _routes.get_children():
			if child.has_meta(&"to"):
				routes.append({"body": child.get_meta(&"to"), "chosen": child.get_meta(&"chosen")})
	return routes


## The ores a plate or card lists for `shown_region` (commonest first): the signature ores of a
## body that can't be reached yet are null ("?").
func shown_ores(shown_region: Region) -> Array[OreType]:
	var system: StarSystem = get_system()
	if not system:
		return []
	var shown_body: CelestialBody = system.body_of(shown_region)
	var ores: Array[OreType] = system.ores_of(shown_region)
	if shown_body and not shown_body.is_reachable():
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


## Whether `item` can be zoomed into: a reachable body, an open region (not the star).
func is_reachable(item: Resource) -> bool:
	var shown_body := item as CelestialBody
	if shown_body:
		return shown_body.is_reachable()
	var shown_region := item as Region
	return shown_region != null and shown_region.unlocked


## The mission on offer for `item` (a region), or null.
func get_offer(item: Resource) -> MissionBrief:
	var shown_region := item as Region
	return mission.offer_for(shown_region) if mission and shown_region else null


## Zooms in a whole step: into the selected body, or into the selected region's landing site; at
## a landing site, chooses it as the destination. Returns whether it did.
func activate() -> bool:
	if level == Level.REGION:
		return choose_destination()
	var before: float = zoom_target
	set_zoom_target(floorf(zoom_target + 0.001) + 1.0)
	return zoom_target > before + 0.5


## Chooses the selected region (or the one whose landing site is shown) as the destination.
## Returns whether it is the destination.
func choose_destination() -> bool:
	var picked := selected.item as Region if selected else null
	var offer: MissionBrief = get_offer(picked)
	if not offer or not picked.unlocked:
		return false
	return offer == mission.destination or mission.choose(offer)


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
## what can't be reached: the star, a station or locked body, a locked region. Reaching a landing
## site shows it (`Mission.preview`), without choosing it.
func set_zoom_target(value: float) -> void:
	value = clampf(value, 0.0, 2.0)
	var from_level: Level = _level_of(zoom_target)
	if from_level == Level.SYSTEM and value > 0.0:
		if selected:
			body = selected.item as CelestialBody
		if not body or not body.is_reachable():
			value = minf(value, UNREACHABLE_LIMIT)
		elif not _globe or _globe.get_meta(&"body", null) != body:
			_build_globe()
	if from_level == Level.BODY and value > 1.0:
		var towards := selected.item as Region if selected else null
		if towards:
			region = towards
		if value >= 2.0 - 0.001 and not _show_landing_site():
			value = minf(value, 1.0 + UNREACHABLE_LIMIT)
		elif not region or not region.unlocked:
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
	if _parts_level != Level.BODY or not _globe:
		return super(camera, screen_position)
	# A ray against the globe: the region whose area it hits.
	var origin: Vector3 = (
		_globe.global_transform.affine_inverse() * camera.project_ray_origin(screen_position)
	)
	var direction: Vector3 = (
		(_globe.global_basis.inverse() * camera.project_ray_normal(screen_position)).normalized()
	)
	var hit: Variant = Geometry3D.segment_intersects_sphere(
		origin, origin + direction * 100.0, Vector3.ZERO, globe_radius
	)
	if hit is PackedVector3Array and not (hit as PackedVector3Array).is_empty():
		var surface: Vector3 = (hit as PackedVector3Array)[0].normalized()
		var best: StationPart = null
		var best_angle: float = deg_to_rad(region_reach)
		for part: StationPart in _parts:
			var angle: float = surface.angle_to(part.position.normalized())
			if angle < best_angle:
				best = part
				best_angle = angle
		return best
	return null


func _card_position(camera: Camera3D) -> Vector3:
	var view: Basis = camera.global_basis
	return _view.global_position + view.x * card_spot.x + view.y * card_spot.y


## Builds the hologram again (e.g. once regions were unlocked: it shows what can be reached),
## keeping what it shows.
func rebuild_hologram() -> void:
	if not _system:
		# Not shown yet: it's built with what can be reached when it first is.
		return
	for view: Node3D in [_system, _globe]:
		if view:
			_view.remove_child(view)
			view.queue_free()
	_system = null
	_globe = null
	_globe_material = null
	_body_parts.clear()
	_system_materials.clear()
	_system_plates.clear()
	_region_plates.clear()
	_routes = null
	_build_system()
	_jump(zoom_target)


## Jumps to `value` without easing (opening, showing a body or region directly).
func _jump(value: float) -> void:
	zoom_target = value
	zoom = value
	_rebuild(_level_of(value))
	_show_zoom()


## Shows the region's landing site on the holo table (just looking). Returns whether it does.
func _show_landing_site() -> bool:
	if not region or not region.unlocked:
		return false
	var offer: MissionBrief = get_offer(region)
	return offer != null and (offer == mission.previewed or mission.preview(offer))


## At a landing site, keeps showing it (after a run, its region offers a new section).
func _keep_landing_site_shown() -> void:
	if level == Level.REGION and region and get_offer(region) != mission.previewed:
		_show_landing_site()


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
			_build_system()
			for node: Node in _system.get_children():
				if node is StationPart:
					_parts.append(node as StationPart)
			focus = body
		Level.BODY:
			if not _globe or _globe.get_meta(&"body", null) != body:
				_build_globe()
			for node: Node in _globe.get_children():
				if node is StationPart:
					_parts.append(node as StationPart)
			focus = region
		Level.REGION:
			_site = StationPart.new()
			_site.item = region
			_site.pick_radius = 0.4
			_view.add_child(_site)
			_parts.append(_site)
	if user:
		var focused: StationPart = get_part(focus) if focus else null
		select(focused if focused else (_parts[0] if not _parts.is_empty() else null))


## Places the views for `zoom`: the system grows around the body until it becomes the globe, the
## globe around the region until the landing site takes over.
func _show_zoom() -> void:
	var stage: float = clampf(zoom, 0.0, 2.0)
	if _system:
		_system.visible = stage < 1.0
		if stage < 1.0 and body and _body_parts.has(body):
			var anchor: Vector3 = _body_parts[body].position
			var grow: float = globe_radius * 2.0 / (body.size * body_scale)
			_zoom_into(_system, anchor, grow, stage)
		else:
			_system.transform = Transform3D.IDENTITY
		_fade_system(1.0 - _crossfade(stage))
	var globe_fade: float = _crossfade(stage) if stage < 1.0 else 1.0 - _crossfade(stage - 1.0)
	if _globe and _globe_material:
		_globe.visible = globe_fade > 0.0
		if stage >= 1.0 and region:
			_zoom_into(_globe, _region_dir(region) * globe_radius, REGION_ZOOM, stage - 1.0)
		else:
			_globe.transform = Transform3D.IDENTITY
		_globe_material.set_shader_parameter(&"fade", globe_fade)
		_update_globe_highlight()
		# The plates step aside once the zoom heads into a region.
		_show_region_plates(globe_fade * (1.0 - smoothstep(1.0, 1.15, stage)))
	if holo_table:
		var site: float = _crossfade(stage - 1.0) if stage >= 1.0 else 0.0
		holo_table.show_hologram(site > 0.0)
		holo_table.set_hologram_scale(lerpf(0.3, 1.0, site) * LANDING_SCALE)


## Scales `node` by up to `grow` (eased by `t` 0–1) around `anchor` (in its space), moving the
## anchor to the view's center on the way.
static func _zoom_into(node: Node3D, anchor: Vector3, grow: float, t: float) -> void:
	var scale_now: float = pow(grow, t)
	node.transform = Transform3D(Basis.from_scale(Vector3.ONE * scale_now), -anchor * t * scale_now)


## How far the next view has faded in at `t` (0–1) of a zoom step.
static func _crossfade(t: float) -> float:
	return smoothstep(CROSSFADE_FROM, 1.0, t)


func _fade_system(fade: float) -> void:
	for material: ShaderMaterial in _system_materials:
		material.set_shader_parameter(&"energy", _system_materials[material] * fade)
	# Plates only at the system view itself: zooming away, they'd grow huge.
	var plates_fade: float = fade * (1.0 - smoothstep(0.0, 0.25, zoom))
	for plate: HoloPlate in _system_plates:
		plate.visible = plates_fade > 0.02
		plate.opacity = _system_plates[plate] * plates_fade


## Shows the globe's region plates facing the camera (`fade`: the globe's), hiding the ones on its
## far side.
func _show_region_plates(fade: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	for plate: HoloPlate in _region_plates:
		var facing: float = 1.0
		if camera:
			var center: Vector3 = _globe.global_position
			var out: Vector3 = (_globe.global_basis * _region_plates[plate]).normalized()
			facing = out.dot((camera.global_position - center).normalized())
		var shown: float = fade * smoothstep(PLATE_FACING_FROM, PLATE_FACING_FULL, facing)
		var region_shown := plate.get_meta(&"region") as Region
		plate.visible = shown > 0.02
		plate.opacity = shown * (1.0 if region_shown.unlocked else UNREACHABLE_FADE + 0.25)


## The star in the middle (its part shows the system's name), the orbit lines, and a part per
## body: a sphere for planets and moons, a station shape for stations; what can't be reached is
## see-through.
func _build_system() -> void:
	if _system:
		return
	var system: StarSystem = get_system()
	if not system:
		return
	_system = Node3D.new()
	_system.name = "System"
	_view.add_child(_system)
	var placed: Dictionary[CelestialBody, Vector3] = {}
	for shown_body: CelestialBody in system.bodies:
		var angle: float = deg_to_rad(shown_body.orbit_angle)
		var radius: float = display_orbit(shown_body)
		var center: Vector3 = placed.get(shown_body.orbits, Vector3.ZERO)
		placed[shown_body] = center + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var orbit: MeshInstance3D = _hologram_mesh(_ring_mesh(radius, 0.006), ORBIT_COLOR, 0.35)
		orbit.position = center
		_system.add_child(orbit)
		var part := StationPart.new()
		part.item = shown_body
		part.pick_radius = shown_body.size * body_scale * 0.6 + 0.1
		part.position = placed[shown_body]
		_system.add_child(part)
		var reach: float = 1.0 if shown_body.is_reachable() else UNREACHABLE_FADE
		var shape: Node3D = (
			_station_shape(shown_body, reach)
			if shown_body.kind == CelestialBody.Kind.STATION
			else _hologram_mesh(_sphere_mesh(shown_body.size * body_scale), shown_body.color, reach)
		)
		part.add_child(shape)
		part.outline = shape
		_body_parts[shown_body] = part
		_add_body_plate(shown_body, part)
	var star := StationPart.new()
	star.item = system
	star.pick_radius = body_scale * 0.8
	_system.add_child(star)
	var star_sphere: MeshInstance3D = _hologram_mesh(
		_sphere_mesh(body_scale * 1.4), system.star_color, 1.0
	)
	star.add_child(star_sphere)
	star.outline = star_sphere
	_build_routes()


## A plate below `shown_body` (in its `part`): its name, and its signature ore ("?" while it can't
## be reached).
func _add_body_plate(shown_body: CelestialBody, part: StationPart) -> void:
	var ores: Array[OreType] = []
	for ore_type: OreType in shown_body.signature_ores:
		ores.append(ore_type if shown_body.is_reachable() else null)
	var plate := HoloPlate.new(tr(shown_body.display_name), ores, -1, Color.WHITE, 40)
	# Below a planet, above a moon: so a planet's and its moons' plates don't overlap.
	var side: Vector3 = Vector3.UP if shown_body.orbits else Vector3.DOWN
	plate.position = (
		side * (shown_body.size * body_scale * 0.5 + (0.1 if shown_body.orbits else 0.05))
	)
	part.add_child(plate)
	_system_plates[plate] = 1.0 if shown_body.is_reachable() else UNREACHABLE_FADE + 0.25


## The ship's marker above the body it's at, a route from there to the destination's body and
## fainter ones to every other body it can go to.
func _build_routes() -> void:
	if not _system:
		return
	if _routes:
		_system.remove_child(_routes)
		_routes.queue_free()
	_routes = Node3D.new()
	_routes.name = "Routes"
	_system.add_child(_routes)
	var from: CelestialBody = ship_body()
	if not from or not _body_parts.has(from):
		return
	var start: Vector3 = _body_parts[from].position
	var marker := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 0.0
	cone.height = 0.1
	cone.radial_segments = 3
	marker.mesh = cone
	marker.material_override = _route_material(SHIP_COLOR, 1.6)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.position = start + Vector3.UP * (from.size * body_scale * 0.5 + 0.1)
	marker.name = "Ship"
	_routes.add_child(marker)
	var target: CelestialBody = null
	var system: StarSystem = get_system()
	if mission and mission.destination and mission.destination.region and system:
		target = system.body_of(mission.destination.region)
	for other: CelestialBody in _body_parts:
		if other == from or not other.is_reachable():
			continue
		var chosen: bool = other == target
		var route: Node3D = _route(start, _body_parts[other].position, chosen)
		route.set_meta(&"to", other)
		route.set_meta(&"chosen", chosen)
		_routes.add_child(route)


## A dotted arc from `start` to `end` (bright for the destination's route).
func _route(start: Vector3, end: Vector3, chosen: bool) -> Node3D:
	var lift: Vector3 = Vector3.UP * start.distance_to(end) * ROUTE_ARC
	var middle: Vector3 = (start + end) * 0.5 + lift
	var count: int = maxi(ceili(start.distance_to(end) / ROUTE_STEP), 2)
	var dot := SphereMesh.new()
	var radius: float = 0.014 if chosen else 0.009
	dot.radius = radius
	dot.height = radius * 2.0
	dot.radial_segments = 6
	dot.rings = 3
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = dot
	# Leave the ends free: they'd sit inside the bodies.
	multimesh.instance_count = maxi(count - 3, 1)
	for i: int in multimesh.instance_count:
		var t: float = float(i + 2) / count
		var at: Vector3 = start.lerp(middle, t).lerp(middle.lerp(end, t), t)
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
	var dots := MultiMeshInstance3D.new()
	dots.multimesh = multimesh
	dots.material_override = _route_material(
		SHIP_COLOR if chosen else ROUTE_COLOR, 2.0 if chosen else 1.0
	)
	dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return dots


## The hologram material of the routes in `color`, one per color; it fades with the system view.
func _route_material(color: Color, energy: float) -> ShaderMaterial:
	if not _route_materials.has(color):
		_route_materials[color] = HoloTable.hologram_material(color)
	var material: ShaderMaterial = _route_materials[color]
	_system_materials[material] = HOLOGRAM_ENERGY * energy
	return material


## A station in the system view: a ring around a hub, with two spokes.
func _station_shape(station: CelestialBody, reach: float) -> Node3D:
	var size: float = station.size * body_scale
	var shape := Node3D.new()
	shape.add_child(_hologram_mesh(_ring_mesh(size * 0.5, size * 0.08), station.color, reach))
	var hub := CylinderMesh.new()
	hub.top_radius = size * 0.12
	hub.bottom_radius = size * 0.12
	hub.height = size * 0.5
	shape.add_child(_hologram_mesh(hub, station.color, reach))
	for turn: float in [0.0, PI * 0.5]:
		var spoke := BoxMesh.new()
		spoke.size = Vector3(size, size * 0.05, size * 0.05)
		var mesh: MeshInstance3D = _hologram_mesh(spoke, station.color, reach)
		mesh.rotation.y = turn
		shape.add_child(mesh)
	# Tilted towards the camera, so the ring reads as a ring.
	shape.rotation.x = deg_to_rad(50.0)
	return shape


func _build_globe() -> void:
	if _globe:
		_view.remove_child(_globe)
		_globe.queue_free()
	_globe = Node3D.new()
	_globe.name = "Globe"
	_globe.set_meta(&"body", body)
	_globe.visible = false
	_view.add_child(_globe)
	_globe_material = null
	if not body:
		return
	var mesh := SphereMesh.new()
	mesh.radius = globe_radius
	mesh.height = globe_radius * 2.0
	mesh.radial_segments = 64
	mesh.rings = 32
	var sphere := MeshInstance3D.new()
	sphere.name = "Sphere"
	sphere.mesh = mesh
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_globe_material = ShaderMaterial.new()
	_globe_material.shader = preload("res://assets/shaders/region_globe.gdshader")
	_globe_material.set_shader_parameter(&"globe_color", body.color)
	_globe_material.set_shader_parameter(&"max_angle", deg_to_rad(region_reach))
	var dirs: PackedVector3Array = []
	var colors: PackedColorArray = []
	var edges: PackedColorArray = []
	_region_plates.clear()
	for shown_region: Region in body.regions:
		var dir: Vector3 = _region_dir(shown_region)
		dirs.append(dir)
		var reach: float = 1.0 if shown_region.unlocked else UNREACHABLE_FADE
		var color: Color = shown_region.biome.map_color if shown_region.biome else Color.WHITE
		colors.append(Color(color, reach))
		edges.append(Color(NavigatorCard.DANGER_COLORS[shown_region.danger], reach))
		var plate := HoloPlate.new(
			tr(shown_region.display_name),
			shown_ores(shown_region),
			shown_region.danger,
			NavigatorCard.DANGER_COLORS[shown_region.danger],
			44
		)
		plate.set_meta(&"region", shown_region)
		plate.position = dir * (globe_radius + 0.04)
		plate.visible = false
		_globe.add_child(plate)
		_region_plates[plate] = dir
		var part := StationPart.new()
		part.item = shown_region
		part.pick_radius = 0.2
		part.position = dir * globe_radius
		_globe.add_child(part)
	_globe_material.set_shader_parameter(&"region_dirs", dirs)
	_globe_material.set_shader_parameter(&"region_colors", colors)
	_globe_material.set_shader_parameter(&"region_edges", edges)
	_globe_material.set_shader_parameter(&"region_count", body.regions.size())
	sphere.material_override = _globe_material
	_globe.add_child(sphere)


## Shows the selected and the hovered region on the globe.
func _update_globe_highlight() -> void:
	# Not a ternary: it would give an untyped array when there's no body (the star is selected).
	var regions: Array[Region] = []
	if body:
		regions = body.regions
	var picked: int = regions.find(selected.item as Region) if selected else -1
	var under: int = regions.find(hovered.item as Region) if hovered else -1
	_globe_material.set_shader_parameter(&"selected", picked)
	_globe_material.set_shader_parameter(&"hovered", under)


## Where `shown_region`'s center lies on its body's globe (a unit direction): latitude up,
## longitude around, 0° facing the camera side (+Z).
static func _region_dir(shown_region: Region) -> Vector3:
	var latitude: float = deg_to_rad(shown_region.globe_position.x)
	var longitude: float = deg_to_rad(shown_region.globe_position.y)
	return Vector3(sin(longitude) * cos(latitude), sin(latitude), cos(longitude) * cos(latitude))


## A mesh in the system view with a hologram material in `color` (`reach`: dimmer when it can't be
## reached); it fades with the system view.
func _hologram_mesh(mesh: Mesh, color: Color, reach: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material: ShaderMaterial = HoloTable.hologram_material(color)
	_system_materials[material] = HOLOGRAM_ENERGY * reach
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _sphere_mesh(diameter: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = diameter * 0.5
	mesh.height = diameter
	mesh.radial_segments = 24
	mesh.rings = 12
	return mesh


## A flat ring (an orbit, a station's ring) of `radius` and `thickness`, in m.
static func _ring_mesh(radius: float, thickness: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius + thickness
	mesh.rings = 96
	mesh.ring_segments = 6
	return mesh
