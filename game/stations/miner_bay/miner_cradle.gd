class_name MinerCradle
extends StationPart
## One cradle of the miners' bay (`MinerBayStation`), for the crafted miner with its `number`: a
## small stowed miner with its number plate above it. A built miner shows as itself (hidden while
## it's on the maintenance pad), one being built as a see-through miner filling from the bottom,
## an empty cradle (also a lost miner's) as a faint outline with "Build". A cradle the ship doesn't
## have (see `Cradles`) is a stripped spot: bare floor rails, cut cables capped and taped, a faded
## ring on the floor where its base stood and its number plate. It builds its look in code from
## `model_scene` (its parts named like the miner's, see `Miner`).

enum Look { BUILT, ON_PAD, BUILDING, EMPTY, MISSING }

## How big the stowed miner is, compared to one on the planet.
const MODEL_SCALE: float = 0.35
## Height of the stowed miner, in m (the miner model is 3.6 m tall).
const MODEL_HEIGHT: float = 3.6 * MODEL_SCALE
const PLATE_COLOR := Color(0.95, 0.95, 0.9)
const PLATE_DIM := Color(0.95, 0.95, 0.9, 0.45)
const BUILD_COLOR := Color(1.0, 0.75, 0.3)
## The faded ring where a missing cradle's base stood: its color (the floor stayed cleaner there).
const FADED_COLOR := Color(0.85, 0.9, 0.95, 0.08)
const TAPE_COLOR := Color(0.75, 0.55, 0.15)
## Where the cut cables come out of the floor at the back.
const CABLE_SPOTS: Array[Vector3] = [
	Vector3(-0.18, 0.0, -0.58), Vector3(0.0, 0.0, -0.62), Vector3(0.2, 0.0, -0.56)
]
const GHOST_SHADER: Shader = preload("res://game/stations/miner_bay/miner_ghost.gdshader")
const METAL: Material = preload("res://game/ship/materials/prop.tres")

## The cradle's number, 1–`MinerFleet.SLOTS`.
var number: int = 1
var look: Look = Look.BUILT

var _model: Node3D
var _base := MeshInstance3D.new()
var _stripped := Node3D.new()
var _plate := Label3D.new()
var _ghost := ShaderMaterial.new()


## Builds the cradle for miner `cradle` with a stowed `model_scene`.
func setup(cradle: int, model_scene: PackedScene) -> void:
	number = cradle
	name = "Cradle%d" % cradle
	pick_radius = 0.6
	_base.name = "Base"
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.6
	base_mesh.bottom_radius = 0.62
	base_mesh.height = 0.08
	base_mesh.material = METAL
	_base.mesh = base_mesh
	_base.position.y = 0.04
	add_child(_base)
	_build_stripped()
	_model = model_scene.instantiate() as Node3D
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	_model.position.y = 0.08
	add_child(_model)
	outline = _model
	_ghost.shader = GHOST_SHADER
	_plate.name = "Plate"
	_plate.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_plate.pixel_size = 0.005
	_plate.font_size = 48
	_plate.outline_size = 12
	_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_plate.position.y = MODEL_HEIGHT + 0.35
	_plate.layers = RenderLayers.EFFECTS
	add_child(_plate)
	position.y = 0.0
	show_look(Look.EMPTY)


## Shows `shown`; `progress` (0–1) is how far a build is.
func show_look(shown: Look, progress: float = 0.0) -> void:
	var missing: bool = shown == Look.MISSING
	_base.visible = not missing
	_stripped.visible = missing
	outline = _stripped if missing else _model
	var ghost: bool = shown in [Look.BUILDING, Look.EMPTY]
	if shown != look or ghost:
		for mesh: MeshInstance3D in _meshes():
			mesh.material_override = _ghost if ghost else null
			mesh.layers = RenderLayers.EFFECTS if ghost else RenderLayers.WORLD
			mesh.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if ghost
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			)
	look = shown
	_model.visible = shown != Look.ON_PAD and not missing
	var bottom: float = _model.global_position.y if _model.is_inside_tree() else 0.0
	_ghost.set_shader_parameter(
		&"fill_top", bottom + MODEL_HEIGHT * progress if shown == Look.BUILDING else -1000.0
	)
	var plate: String = CraftedMiner.plate_of(number)
	_plate.text = plate + "\n" + tr("Build") if shown == Look.EMPTY else plate
	_plate.modulate = PLATE_DIM if shown in [Look.ON_PAD, Look.MISSING] else PLATE_COLOR
	if shown == Look.EMPTY:
		_plate.modulate = BUILD_COLOR


## The stripped spot of a cradle the ship doesn't have: two bare rails on the floor, three cables
## cut off at the back, capped and taped, and a faded ring on the floor where its base stood.
func _build_stripped() -> void:
	_stripped.name = "Stripped"
	add_child(_stripped)
	for side: float in [-0.32, 0.32]:
		_part(BoxMesh.new(), Vector3(0.07, 0.03, 1.0), Vector3(side, 0.015, -0.1), METAL)
	var cable := StandardMaterial3D.new()
	cable.albedo_color = Color(0.06, 0.06, 0.07)
	cable.roughness = 0.7
	var tape := StandardMaterial3D.new()
	tape.albedo_color = TAPE_COLOR
	tape.roughness = 0.8
	for spot: Vector3 in CABLE_SPOTS:
		var height: float = 0.22 + absf(spot.x) * 0.4
		_part(
			CylinderMesh.new(), Vector3(0.05, height, 0.05), spot + Vector3.UP * height * 0.5, cable
		)
		_part(
			CylinderMesh.new(), Vector3(0.06, 0.05, 0.06), spot + Vector3.UP * (height - 0.06), tape
		)
		_part(CylinderMesh.new(), Vector3(0.065, 0.03, 0.065), spot + Vector3.UP * height, METAL)
	var faded := StandardMaterial3D.new()
	faded.albedo_color = FADED_COLOR
	faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	faded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.57
	ring_mesh.outer_radius = 0.62
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 4
	ring_mesh.material = faded
	var ring := MeshInstance3D.new()
	ring.name = "Faded"
	ring.mesh = ring_mesh
	ring.scale.y = 0.05
	ring.position.y = 0.01
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stripped.add_child(ring)


## Adds a piece of the stripped spot: `mesh` sized `extent` (a cylinder's diameter in x) at `at`.
func _part(mesh: PrimitiveMesh, extent: Vector3, at: Vector3, material: Material) -> void:
	var cylinder := mesh as CylinderMesh
	if cylinder:
		cylinder.top_radius = extent.x * 0.5
		cylinder.bottom_radius = extent.x * 0.5
		cylinder.height = extent.y
		cylinder.radial_segments = 10
		cylinder.rings = 1
	else:
		(mesh as BoxMesh).size = extent
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	_stripped.add_child(instance)


func _meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	return meshes
