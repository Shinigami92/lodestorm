class_name HeatShieldStation
extends Station
## The drive core in the engine room with the ship's heat shield around it (see GAME_DESIGN.md,
## Opening planets; greybox until the ship's art pass): a ring of plates stacked around the core,
## one per planet inwards (MK2 at the bottom, the last one at the top; MK1 is the bare core).
## Installed plates glow, the next one fills up as it's paid (from left to right over the ring's
## side facing the camera, like a silo's gauge), later ones show as dim outlines, so the length
## of the way stays visible. Each plate is a part (its `item` the `ShieldPlate`); the card
## (`HeatShieldCard`) shows the selected one, and for the next one makes it the ship's project or
## pays the rest from the hold. Only the host can (the ship and the open bodies are the host's
## save), and nothing while a mission is underway.

const CORE_RADIUS: float = 0.95
const CORE_HEIGHT: float = 3.3
## The plates' rings: radius, height, the gap between them and the lowest one's bottom, in m.
const PLATE_RADIUS: float = 1.4
const PLATE_THICKNESS: float = 0.08
const PLATE_HEIGHT: float = 0.42
const PLATE_GAP: float = 0.1
const PLATE_BOTTOM: float = 0.4
## Segments around a full ring.
const SEGMENTS: int = 48
## How far around the ring the fill reaches either side of the front (+Z), in radians: the part
## the camera sees.
const FRONT_ARC: float = PI * 0.62
const HEAT_COLOR := Color(1.0, 0.55, 0.2)
const OUTLINE_COLOR := Color(0.3, 0.85, 1.0, 0.35)
## Where the card floats, from the core's axis: right and up on screen, in m.
const CARD_SPOT := Vector2(2.45, 1.75)

var _parts: Array[StationPart] = []
## Per plate (by its part): its shell, the glowing fill of what's paid, the outline edges.
var _shells: Dictionary[StationPart, MeshInstance3D] = {}
var _fills: Dictionary[StationPart, MeshInstance3D] = {}
var _edges: Dictionary[StationPart, Array] = {}
var _watched: HeatShield
var _installed_material := StandardMaterial3D.new()
var _next_material := StandardMaterial3D.new()
var _fill_material := StandardMaterial3D.new()
var _outline_material := StandardMaterial3D.new()


func _init() -> void:
	super()
	locks_while_underway = true


func _ready() -> void:
	_build_materials()
	_build_plates(HeatShield.PLATES.plates)
	super()


func _process(delta: float) -> void:
	super(delta)
	var shield: HeatShield = get_heat_shield()
	if shield != _watched:
		if _watched:
			_watched.changed.disconnect(update_plates)
		_watched = shield
		if shield:
			shield.changed.connect(update_plates)
		update_plates()
	# The hold or the mission may change meanwhile.
	if user:
		refresh()


## The ship's heat shield, or null.
func get_heat_shield() -> HeatShield:
	return ship.heat_shield if ship else null


func get_parts() -> Array[StationPart]:
	return _parts.duplicate()


## The part of the plate that brings MK `level`, or null.
func get_plate_part(level: int) -> StationPart:
	var index: int = level - 2
	return _parts[index] if index >= 0 and index < _parts.size() else null


## The MK level `part`'s plate brings (0: not a plate).
func level_of(part: StationPart) -> int:
	var index: int = _parts.find(part)
	return index + 2 if index >= 0 else 0


## The names of the bodies plate MK `level` opens (translated): those of that tier with regions.
func opened_by(level: int) -> PackedStringArray:
	var names: PackedStringArray = []
	var voyage: Voyage = ship.voyage if ship else null
	var system: StarSystem = voyage.settings.system if voyage and voyage.settings else null
	if system:
		for body: CelestialBody in system.bodies:
			if body.tier == level and body.is_reachable(level):
				names.append(tr(body.display_name))
	return names


## Whether the player using it may pick the ship's project and pay into it: only the host.
func is_host() -> bool:
	return multiplayer.is_server()


## Whether plate MK `level` can be worked on now: it's the next one, someone uses the station,
## they're the host and no mission is underway.
func can_work_on(level: int) -> bool:
	var shield: HeatShield = get_heat_shield()
	return (
		shield != null and level == shield.mk + 1 and user != null and is_host() and not is_locked()
	)


## Makes plate MK `level` the ship's project. Returns whether it did.
func set_project(level: int) -> bool:
	if not can_work_on(level) or not get_heat_shield().set_project():
		return false
	refresh()
	return true


## Pays what plate MK `level` still needs from the host's hold, as far as it goes. Returns whether
## it paid anything.
func pay(level: int) -> bool:
	if not can_work_on(level) or not ship.pay_shield(user.hold):
		return false
	refresh()
	return true


## Shows each plate by its state: installed, the next one filled as far as it's paid, later ones
## as outlines.
func update_plates() -> void:
	var shield: HeatShield = get_heat_shield()
	var mk: int = shield.mk if shield else 1
	for part: StationPart in _parts:
		var level: int = level_of(part)
		var shell: MeshInstance3D = _shells[part]
		shell.visible = level <= mk + 1
		shell.material_override = _installed_material if level <= mk else _next_material
		for edge: MeshInstance3D in _edges[part]:
			edge.visible = level > mk + 1
		var fill: MeshInstance3D = _fills[part]
		var paid: float = _paid_fraction(shield) if level == mk + 1 else 0.0
		fill.visible = paid > 0.0
		if fill.visible:
			fill.mesh = _arc_mesh(PLATE_RADIUS + PLATE_THICKNESS * 0.5 + 0.01, PLATE_HEIGHT, paid)


## The camera frames the core and the card beside it.
func _card_position(camera: Camera3D) -> Vector3:
	var view: Basis = camera.global_basis
	return global_position + view.x * CARD_SPOT.x + Vector3.UP * CARD_SPOT.y


func _opened() -> void:
	var shield: HeatShield = get_heat_shield()
	if not selected and shield:
		select(get_plate_part(mini(shield.mk + 1, shield.max_mk())))
	super()


func _cycle(step_by: int) -> void:
	if _parts.is_empty():
		return
	select(_parts[posmod(_parts.find(selected) + step_by, _parts.size())])


## How much of the next plate is paid, from 0 to 1 (all its ores together).
static func _paid_fraction(shield: HeatShield) -> float:
	var plate: ShieldPlate = shield.next_plate() if shield else null
	if not plate:
		return 0.0
	var total: float = 0.0
	var paid: float = 0.0
	for ore_type: OreType in plate.cost:
		var paid_so_far: float = shield.paid.get(ore_type, 0.0)
		total += plate.cost[ore_type]
		paid += minf(paid_so_far, plate.cost[ore_type])
	return paid / total if total > 0.0 else 0.0


func _build_materials() -> void:
	_installed_material.albedo_color = HEAT_COLOR.darkened(0.3)
	_installed_material.emission_enabled = true
	_installed_material.emission = HEAT_COLOR
	_installed_material.emission_energy_multiplier = 1.4
	_next_material.albedo_color = Color(0.16, 0.17, 0.19)
	_next_material.metallic = 0.4
	_next_material.roughness = 0.5
	_fill_material.albedo_color = HEAT_COLOR.darkened(0.3)
	_fill_material.emission_enabled = true
	_fill_material.emission = HEAT_COLOR
	_fill_material.emission_energy_multiplier = 1.4
	_fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_material.albedo_color = OUTLINE_COLOR


## A ring per plate around the core, from the bottom up, each with its part at the ring's front.
func _build_plates(plates: Array[ShieldPlate]) -> void:
	var holder := Node3D.new()
	holder.name = "Plates"
	add_child(holder)
	for i: int in plates.size():
		var ring := Node3D.new()
		ring.name = "MK%d" % (i + 2)
		ring.position.y = PLATE_BOTTOM + i * (PLATE_HEIGHT + PLATE_GAP) + PLATE_HEIGHT * 0.5
		holder.add_child(ring)
		# What's outlined while selected: the shell and the edges (not the fill, an open strip).
		var outlined := Node3D.new()
		outlined.name = "Outlined"
		ring.add_child(outlined)
		var shell := MeshInstance3D.new()
		shell.name = "Shell"
		# Closed (with a wall thickness), so the selection outline is a border, not a fill.
		shell.mesh = _ring_mesh(PLATE_RADIUS, PLATE_THICKNESS, PLATE_HEIGHT)
		outlined.add_child(shell)
		var fill := MeshInstance3D.new()
		fill.name = "Fill"
		fill.material_override = _fill_material
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.add_child(fill)
		var edges: Array[MeshInstance3D] = []
		for side: float in [-0.5, 0.5]:
			var edge := MeshInstance3D.new()
			edge.name = "Edge"
			var torus := TorusMesh.new()
			torus.inner_radius = PLATE_RADIUS - 0.015
			torus.outer_radius = PLATE_RADIUS + 0.015
			torus.rings = SEGMENTS
			torus.ring_segments = 6
			edge.mesh = torus
			edge.material_override = _outline_material
			edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			edge.layers = RenderLayers.EFFECTS
			edge.position.y = side * PLATE_HEIGHT
			outlined.add_child(edge)
			edges.append(edge)
		var part := StationPart.new()
		part.name = "Part"
		part.item = plates[i]
		part.position = Vector3(0.0, 0.0, PLATE_RADIUS)
		part.pick_radius = 0.45
		part.outline = outlined
		ring.add_child(part)
		_parts.append(part)
		_shells[part] = shell
		_fills[part] = fill
		_edges[part] = edges


## A closed ring around the axis: `radius` to the middle of its wall, `thickness` and `height`.
static func _ring_mesh(radius: float, thickness: float, height: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: float = radius - thickness * 0.5
	var outer: float = radius + thickness * 0.5
	var up := Vector3.UP * height * 0.5
	for i: int in SEGMENTS:
		var a := Vector3(sin(TAU * i / SEGMENTS), 0.0, cos(TAU * i / SEGMENTS))
		var b := Vector3(sin(TAU * (i + 1) / SEGMENTS), 0.0, cos(TAU * (i + 1) / SEGMENTS))
		var ao: Vector3 = a * outer
		var bo: Vector3 = b * outer
		var ai: Vector3 = a * inner
		var bi: Vector3 = b * inner
		# The outer wall, the inner wall, the top and the bottom.
		_add_quad(tool, [ao + up, bo + up, bo - up, ao - up], [a, b, b, a])
		_add_quad(tool, [bi + up, ai + up, ai - up, bi - up], [-b, -a, -a, -b])
		_add_quad(
			tool,
			[ai + up, bi + up, bo + up, ao + up],
			[Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]
		)
		_add_quad(
			tool,
			[ao - up, bo - up, bi - up, ai - up],
			[Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN]
		)
	return tool.commit()


## Two triangles from `corners` (clockwise seen from outside, Godot's front faces) with their
## `normals`.
static func _add_quad(tool: SurfaceTool, corners: Array[Vector3], normals: Array[Vector3]) -> void:
	for i: int in [0, 1, 2, 0, 2, 3]:
		tool.set_normal(normals[i])
		tool.add_vertex(corners[i])


## A band of a ring of `radius` and `height` around the axis, from the left end of the side facing
## the camera (`FRONT_ARC` left of the front, +Z) over `fraction` of that side.
static func _arc_mesh(radius: float, height: float, fraction: float) -> ArrayMesh:
	var from: float = -FRONT_ARC
	var to: float = lerpf(-FRONT_ARC, FRONT_ARC, clampf(fraction, 0.0, 1.0))
	var steps: int = maxi(ceili(SEGMENTS * (to - from) / TAU), 1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for i: int in steps + 1:
		var angle: float = lerpf(from, to, float(i) / steps)
		var out := Vector3(sin(angle), 0.0, cos(angle))
		vertices.append(out * radius + Vector3.UP * height * 0.5)
		vertices.append(out * radius - Vector3.UP * height * 0.5)
		normals.append(out)
		normals.append(out)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	return mesh
