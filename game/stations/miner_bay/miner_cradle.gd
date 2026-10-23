class_name MinerCradle
extends StationPart
## One cradle of the miners' bay (`MinerBayStation`), for the crafted miner with its `number`: a
## small stowed miner with its number plate above it. A built miner shows as itself (hidden while
## it's on the maintenance pad), one being built as a see-through miner filling from the bottom,
## an empty cradle (also a lost miner's) as a faint outline with "Build". It builds its look in
## code from `model_scene` (its parts named like the miner's, see `Miner`).

enum Look { BUILT, ON_PAD, BUILDING, EMPTY }

## How big the stowed miner is, compared to one on the planet.
const MODEL_SCALE: float = 0.35
## Height of the stowed miner, in m (the miner model is 3.6 m tall).
const MODEL_HEIGHT: float = 3.6 * MODEL_SCALE
const PLATE_COLOR := Color(0.95, 0.95, 0.9)
const PLATE_DIM := Color(0.95, 0.95, 0.9, 0.45)
const BUILD_COLOR := Color(1.0, 0.75, 0.3)
const GHOST_SHADER: Shader = preload("res://game/stations/miner_bay/miner_ghost.gdshader")

## The cradle's number, 1–`MinerFleet.SLOTS`.
var number: int = 1
var look: Look = Look.BUILT

var _model: Node3D
var _plate := Label3D.new()
var _ghost := ShaderMaterial.new()


## Builds the cradle for miner `cradle` with a stowed `model_scene`.
func setup(cradle: int, model_scene: PackedScene) -> void:
	number = cradle
	name = "Cradle%d" % cradle
	pick_radius = 0.6
	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.6
	base_mesh.bottom_radius = 0.62
	base_mesh.height = 0.08
	base_mesh.material = preload("res://game/ship/materials/prop.tres")
	base.mesh = base_mesh
	base.position.y = 0.04
	add_child(base)
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
	_model.visible = shown != Look.ON_PAD
	var bottom: float = _model.global_position.y if _model.is_inside_tree() else 0.0
	_ghost.set_shader_parameter(
		&"fill_top", bottom + MODEL_HEIGHT * progress if shown == Look.BUILDING else -1000.0
	)
	var plate: String = CraftedMiner.plate_of(number)
	_plate.text = plate + "\n" + tr("Build") if shown == Look.EMPTY else plate
	_plate.modulate = PLATE_DIM if shown == Look.ON_PAD else PLATE_COLOR
	if shown == Look.EMPTY:
		_plate.modulate = BUILD_COLOR


func _meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	return meshes
