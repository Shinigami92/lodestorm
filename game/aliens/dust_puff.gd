class_name DustPuff
extends Node3D
## Dust thrown up where a huge alien's foot lands (`AlienTremor`): a low, flattened cloud that
## swells and fades. Greybox look, TBD (playtest).

## Seconds it lasts.
const DURATION: float = 0.9
## Its size at the start and end, for a puff of strength 1 (m).
const START_RADIUS: float = 0.4
const END_RADIUS: float = 1.4
const COLOR := Color(0.42, 0.38, 0.33, 0.45)

var strength: float = 1.0

var _elapsed: float = 0.0
var _material := StandardMaterial3D.new()
var _cloud: MeshInstance3D


## A puff at `point` (global) in `parent`, `size` times as big as a step's.
static func spawn(parent: Node, point: Vector3, size: float = 1.0) -> DustPuff:
	var puff := DustPuff.new()
	puff.strength = size
	parent.add_child(puff)
	puff.global_transform = Transform3D(Basis.IDENTITY, point)
	return puff


func _ready() -> void:
	_material.albedo_color = COLOR
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 6
	sphere.material = _material
	_cloud = MeshInstance3D.new()
	_cloud.name = "Cloud"
	_cloud.mesh = sphere
	_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cloud)
	_update()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	_update()


func _update() -> void:
	var t: float = _elapsed / DURATION
	var size: float = lerpf(START_RADIUS, END_RADIUS, 1.0 - (1.0 - t) * (1.0 - t)) * strength
	_cloud.scale = Vector3(size, size * 0.35, size)
	_material.albedo_color.a = COLOR.a * (1.0 - t)
