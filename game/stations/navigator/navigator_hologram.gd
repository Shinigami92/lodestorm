class_name NavigatorHologram
extends Node3D
## The navigator's hologram above the bridge's holo table (the `NavigatorStation` it belongs to says
## what's shown): the star system (`System`: the star, an orbit line per body spread evenly so every
## body fits on the table, a hologram sphere per planet and moon, a ring-and-hub shape per station,
## a name plate per body with its signature ore, "?" while out of reach, the ship's marker and
## routes to where it can go, an amber diamond on a station where someone waits) and a body's globe
## (`Globe`: its regions as bordered areas on the surface in their biome's color, a plate per region
## with its name, danger pips and ores). What can't be reached is see-through. `show_zoom` places
## them for the navigator's zoom: the system grows around the body until it becomes the globe, the
## globe around the region until the landing site (the holo table's location hologram) takes over.

## How see-through what can't be reached is.
const UNREACHABLE_FADE: float = 0.35
## How much the globe grows while zooming into a region, and where (of each step) the next view
## starts fading in.
const REGION_ZOOM: float = 4.0
const CROSSFADE_FROM: float = 0.75
const HOLOGRAM_ENERGY: float = 0.9
const ORBIT_COLOR := Color(0.3, 0.85, 1.0)
## The ship's marker and the route to the destination; the routes to the other reachable bodies.
const SHIP_COLOR := Color(1.0, 0.72, 0.3)
const ROUTE_COLOR := Color(0.3, 0.85, 1.0)
## The diamond on a station where someone waits (see `StationWait`): its color and size, in m.
const WAIT_COLOR := Color(1.0, 0.75, 0.3)
const WAIT_SIZE: float = 0.09
## Distance between a route's dots, in m, and how high a route arcs (of its length).
const ROUTE_STEP: float = 0.045
const ROUTE_ARC: float = 0.22
## How far a plate on the globe faces the camera at least to show (cosine), and fully.
const PLATE_FACING_FROM: float = 0.15
const PLATE_FACING_FULL: float = 0.45


## A route drawn in the system view: the body it goes to, and whether it's the destination's.
class Route:
	var body: CelestialBody
	var chosen: bool

	func _init(to: CelestialBody, is_chosen: bool) -> void:
		body = to
		chosen = is_chosen


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

## The station whose hologram it is: what can be reached, the ores shown, the selection; set by it.
var navigator: NavigatorStation

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
## The diamond of each station (its id), shown while someone waits there (`show_waits`).
var _wait_markers: Dictionary[StringName, Node3D] = {}


## Whether the system view is built (it is once the star system is known).
func is_built() -> bool:
	return _system != null


## The system view's parts (one per body, and the star), building it first if needed.
func system_parts() -> Array[StationPart]:
	_build_system()
	return _parts_of(_system)


## `shown_body`'s globe's parts (one per region), building it first if it shows another body.
func globe_parts(shown_body: CelestialBody) -> Array[StationPart]:
	if not _globe or _globe.get_meta(&"body", null) != shown_body:
		_build_globe(shown_body)
	return _parts_of(_globe)


## Removes both views, so they're built again with what can be reached now (e.g. once the heat
## shield got another plate).
func clear() -> void:
	for view: Node3D in [_system, _globe]:
		if view:
			remove_child(view)
			view.queue_free()
	_system = null
	_globe = null
	_globe_material = null
	_body_parts.clear()
	_system_materials.clear()
	_system_plates.clear()
	_region_plates.clear()
	_wait_markers.clear()
	_routes = null


## Shows the diamond on each station in `waiting` (its id: whether the tracked quest waits there,
## then it's filled; else outlined) and hides the others.
func show_waits(waiting: Dictionary[StringName, bool]) -> void:
	for id: StringName in _wait_markers:
		var marker: Node3D = _wait_markers[id]
		marker.visible = waiting.has(id)
		if marker.visible:
			var filled: bool = waiting[id]
			(marker.get_node(^"Filled") as Node3D).visible = filled
			(marker.get_node(^"Outlined") as Node3D).visible = not filled


## How far `shown_body`'s orbit lies from what it orbits in the system view, in m: the star's
## orbits spread evenly from `inner_orbit` to `outer_orbit` in the order of their `orbit_radius`,
## a planet's moons one `moon_orbit` after another outside its surface.
func display_orbit(shown_body: CelestialBody) -> float:
	var system: StarSystem = navigator.get_system()
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


## The name plates of the globe (one per region) or of the system view (one per body).
func get_plates(on_globe: bool) -> Array[HoloPlate]:
	var plates: Array[HoloPlate] = []
	plates.assign(_region_plates.keys() if on_globe else _system_plates.keys())
	return plates


## The routes drawn in the system view.
func get_routes() -> Array[Route]:
	var routes: Array[Route] = []
	if _routes:
		for child: Node in _routes.get_children():
			if child.has_meta(&"to"):
				var to := child.get_meta(&"to") as CelestialBody
				var chosen: bool = child.get_meta(&"chosen")
				routes.append(Route.new(to, chosen))
	return routes


## The region part of the globe under the screen position (a ray against the globe: the region
## whose area it hits), or null.
func globe_part_at(camera: Camera3D, screen_position: Vector2) -> StationPart:
	if not _globe:
		return null
	var origin: Vector3 = (
		_globe.global_transform.affine_inverse() * camera.project_ray_origin(screen_position)
	)
	var direction: Vector3 = (
		(_globe.global_basis.inverse() * camera.project_ray_normal(screen_position)).normalized()
	)
	var hit: Variant = Geometry3D.segment_intersects_sphere(
		origin, origin + direction * 100.0, Vector3.ZERO, globe_radius
	)
	if not (hit is PackedVector3Array and not (hit as PackedVector3Array).is_empty()):
		return null
	var surface: Vector3 = (hit as PackedVector3Array)[0].normalized()
	var best: StationPart = null
	var best_angle: float = deg_to_rad(region_reach)
	for part: StationPart in _parts_of(_globe):
		var angle: float = surface.angle_to(part.position.normalized())
		if angle < best_angle:
			best = part
			best_angle = angle
	return best


## Places the views for `zoom` (0: the system, 1: `shown_body`'s globe, 2: `shown_region`'s
## landing site): the system grows around the body until it becomes the globe, the globe around
## the region until the landing site takes over.
func show_zoom(zoom: float, shown_body: CelestialBody, shown_region: Region) -> void:
	var stage: float = clampf(zoom, 0.0, 2.0)
	if _system:
		_system.visible = stage < 1.0
		if stage < 1.0 and shown_body and _body_parts.has(shown_body):
			var anchor: Vector3 = _body_parts[shown_body].position
			var grow: float = globe_radius * 2.0 / (shown_body.size * body_scale)
			_zoom_into(_system, anchor, grow, stage)
		else:
			_system.transform = Transform3D.IDENTITY
		_fade_system(1.0 - crossfade(stage), zoom)
	var globe_fade: float = crossfade(stage) if stage < 1.0 else 1.0 - crossfade(stage - 1.0)
	if _globe and _globe_material:
		# Not while zooming into a station (its map shows on the table) or another body.
		_globe.visible = globe_fade > 0.0 and _globe.get_meta(&"body", null) == shown_body
		if stage >= 1.0 and shown_region:
			_zoom_into(_globe, _region_dir(shown_region) * globe_radius, REGION_ZOOM, stage - 1.0)
		else:
			_globe.transform = Transform3D.IDENTITY
		_globe_material.set_shader_parameter(&"fade", globe_fade)
		_update_globe_highlight()
		# The plates step aside once the zoom heads into a region.
		_show_region_plates(globe_fade * (1.0 - smoothstep(1.0, 1.15, stage)))


## The ship's marker above the body it's at, a route from there to the destination's body and
## fainter ones to every other body it can go to.
func build_routes() -> void:
	if not _system:
		return
	if _routes:
		_routes.free()
	_routes = Node3D.new()
	_routes.name = "Routes"
	_system.add_child(_routes)
	var from: CelestialBody = navigator.ship_body()
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
	var target: CelestialBody = navigator.destination_body()
	for other: CelestialBody in _body_parts:
		if other == from or not navigator.is_reachable(other):
			continue
		var chosen: bool = other == target
		var route: Node3D = _route(start, _body_parts[other].position, chosen)
		route.set_meta(&"to", other)
		route.set_meta(&"chosen", chosen)
		_routes.add_child(route)
	RenderLayers.put(self, RenderLayers.EFFECTS)


## How far the next view has faded in at `t` (0–1) of a zoom step.
static func crossfade(t: float) -> float:
	return smoothstep(CROSSFADE_FROM, 1.0, t)


static func _parts_of(view: Node3D) -> Array[StationPart]:
	var parts: Array[StationPart] = []
	if view:
		for node: Node in view.get_children():
			if node is StationPart:
				parts.append(node as StationPart)
	return parts


## Scales `node` by up to `grow` (eased by `t` 0–1) around `anchor` (in its space), moving the
## anchor to the view's center on the way.
static func _zoom_into(node: Node3D, anchor: Vector3, grow: float, t: float) -> void:
	var scale_now: float = pow(grow, t)
	node.transform = Transform3D(Basis.from_scale(Vector3.ONE * scale_now), -anchor * t * scale_now)


func _fade_system(fade: float, zoom: float) -> void:
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
		var reach: float = 1.0 if navigator.is_reachable(region_shown) else UNREACHABLE_FADE + 0.25
		plate.opacity = shown * reach


## The star in the middle (its part shows the system's name), the orbit lines, and a part per
## body: a sphere for planets and moons, a station shape for stations; what can't be reached is
## see-through.
func _build_system() -> void:
	if _system:
		return
	var system: StarSystem = navigator.get_system()
	if not system:
		return
	_system = Node3D.new()
	_system.name = "System"
	add_child(_system)
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
		var reach: float = 1.0 if navigator.is_reachable(shown_body) else UNREACHABLE_FADE
		var shape: Node3D = (
			_station_shape(shown_body, reach)
			if shown_body.kind == CelestialBody.Kind.STATION
			else _hologram_mesh(_sphere_mesh(shown_body.size * body_scale), shown_body.color, reach)
		)
		part.add_child(shape)
		part.outline = shape
		_body_parts[shown_body] = part
		_add_body_plate(shown_body, part)
		if shown_body.kind == CelestialBody.Kind.STATION:
			_add_wait_marker(shown_body, part)
	var star := StationPart.new()
	star.item = system
	star.pick_radius = body_scale * 0.8
	_system.add_child(star)
	var star_sphere: MeshInstance3D = _hologram_mesh(
		_sphere_mesh(body_scale * 1.4), system.star_color, 1.0
	)
	star.add_child(star_sphere)
	star.outline = star_sphere
	build_routes()


## A plate below `shown_body` (in its `part`): its name, and its signature ore ("?" while it can't
## be reached).
func _add_body_plate(shown_body: CelestialBody, part: StationPart) -> void:
	var reachable: bool = navigator.is_reachable(shown_body)
	var ores: Array[OreType] = []
	for ore_type: OreType in shown_body.signature_ores:
		ores.append(ore_type if reachable else null)
	var plate := HoloPlate.new(tr(shown_body.display_name), ores, -1, Color.WHITE, 40)
	# Below a planet, above a moon: so a planet's and its moons' plates don't overlap.
	var side: Vector3 = Vector3.UP if shown_body.orbits else Vector3.DOWN
	plate.position = (
		side * (shown_body.size * body_scale * 0.5 + (0.1 if shown_body.orbits else 0.05))
	)
	part.add_child(plate)
	_system_plates[plate] = 1.0 if reachable else UNREACHABLE_FADE + 0.25


## The diamond of `station` (hidden until someone waits there), beside its shape in `part`: filled
## and outlined, one of them shown.
func _add_wait_marker(station: CelestialBody, part: StationPart) -> void:
	var marker := Node3D.new()
	marker.name = "Waiting"
	marker.visible = false
	var reach: float = station.size * body_scale * 0.5
	marker.position = Vector3(reach + WAIT_SIZE * 1.2, reach + WAIT_SIZE * 0.5, 0.0)
	var box := BoxMesh.new()
	box.size = Vector3(WAIT_SIZE, WAIT_SIZE, WAIT_SIZE * 0.4)
	var filled: MeshInstance3D = _hologram_mesh(box, WAIT_COLOR, 1.6)
	filled.name = "Filled"
	filled.rotation.z = PI * 0.25
	marker.add_child(filled)
	# A torus of four segments is a square: stood up, a diamond's outline.
	var edge: float = WAIT_SIZE * 0.1
	var square := TorusMesh.new()
	square.inner_radius = WAIT_SIZE * 0.7 - edge
	square.outer_radius = WAIT_SIZE * 0.7 + edge
	square.rings = 4
	square.ring_segments = 4
	var outlined: MeshInstance3D = _hologram_mesh(square, WAIT_COLOR, 1.6)
	outlined.name = "Outlined"
	outlined.rotation.x = PI * 0.5
	marker.add_child(outlined)
	part.add_child(marker)
	_wait_markers[station.id] = marker


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


func _build_globe(shown_body: CelestialBody) -> void:
	if _globe:
		remove_child(_globe)
		_globe.queue_free()
	_globe = Node3D.new()
	_globe.name = "Globe"
	_globe.set_meta(&"body", shown_body)
	_globe.visible = false
	add_child(_globe)
	_globe_material = null
	_region_plates.clear()
	if not shown_body:
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
	_globe_material.set_shader_parameter(&"globe_color", shown_body.color)
	_globe_material.set_shader_parameter(&"max_angle", deg_to_rad(region_reach))
	var dirs: PackedVector3Array = []
	var colors: PackedColorArray = []
	var edges: PackedColorArray = []
	for shown_region: Region in shown_body.regions:
		var dir: Vector3 = _region_dir(shown_region)
		dirs.append(dir)
		var reach: float = 1.0 if navigator.is_reachable(shown_region) else UNREACHABLE_FADE
		var color: Color = shown_region.biome.map_color if shown_region.biome else Color.WHITE
		colors.append(Color(color, reach))
		edges.append(Color(NavigatorCard.DANGER_COLORS[shown_region.danger], reach))
		var plate := HoloPlate.new(
			tr(shown_region.display_name),
			navigator.shown_ores(shown_region),
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
	_globe_material.set_shader_parameter(&"region_count", shown_body.regions.size())
	sphere.material_override = _globe_material
	_globe.add_child(sphere)
	RenderLayers.put(self, RenderLayers.EFFECTS)


## Shows the navigator's selected and hovered region on the globe.
func _update_globe_highlight() -> void:
	# Not a ternary: it would give an untyped array when there's no body (the star is selected).
	var regions: Array[Region] = []
	var shown_body := _globe.get_meta(&"body", null) as CelestialBody
	if shown_body:
		regions = shown_body.regions
	var selected: StationPart = navigator.selected
	var hovered: StationPart = navigator.hovered
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
