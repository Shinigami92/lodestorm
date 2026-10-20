class_name WeaponBeam
extends WeaponStream
## A beam weapon's beam (see `BeamDelivery`: Kith, Zenith): a glowing line from the muzzle (where
## it's placed) to where the beam ends, flickering, with a glow where it ends; brighter and wider
## while it's `heated` (Zenith staying on a target). It also counts how long the beam stays on
## each target (`dwell`), for a beam that hits harder the longer it stays. Greybox until the art
## pass.

## Width of the line in m, and how much wider it gets when `heated` is full.
@export var width: float = 0.06
@export var heated_width: float = 2.0
@export var color := Color(1.0, 0.9, 0.7)
## The glow where it ends, in m.
@export var end_size: float = 0.5

## How far the beam has heated up on its target, 0 to 1 (set by the delivery every attack).
var heated: float = 0.0

## Seconds the beam has stayed on each target, and the ones it touched in the attack under way.
var _dwell: Dictionary[Node, float] = {}
var _touched: Array[Node] = []
var _line: MeshInstance3D
var _end: MeshInstance3D
var _line_material := StandardMaterial3D.new()
var _end_material := StandardMaterial3D.new()


func _ready() -> void:
	# Made here, not with the node: a weapon freed without entering the tree would leak them.
	_line = MeshInstance3D.new()
	_end = MeshInstance3D.new()
	for material: StandardMaterial3D in [_line_material, _end_material]:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	_line.mesh = box
	_line.material_override = _line_material
	_end_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_end_material.albedo_texture = Burning.soft_dot()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * end_size
	_end.mesh = quad
	_end.material_override = _end_material
	for mesh: MeshInstance3D in [_line, _end]:
		mesh.top_level = true
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visible = false
		add_child(mesh)


## Counts `seconds` more of the beam on `target`, this attack; returns how long it has stayed on.
func dwell(target: Node, seconds: float) -> float:
	_touched.append(target)
	_dwell[target] = _dwell.get(target, 0.0) + seconds
	return _dwell[target]


## Ends an attack at `at`: targets it didn't touch start over.
func fire(at: Vector3) -> void:
	super.fire(at)
	for target: Node in _dwell.keys():
		if not _touched.has(target):
			_dwell.erase(target)
	_touched.clear()


func _show(on: bool, _delta: float) -> void:
	_line.visible = on
	_end.visible = on
	if not on:
		_dwell.clear()
		heated = 0.0
		return
	var from: Vector3 = global_position
	var length: float = maxf(from.distance_to(end), 0.01)
	var direction: Vector3 = from.direction_to(end) if length > 0.01 else -global_basis.z
	var flicker: float = randf_range(0.85, 1.0)
	var thick: float = width * lerpf(1.0, heated_width, heated) * flicker
	var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	_line.global_transform = Transform3D(
		Basis.looking_at(direction, up).scaled_local(Vector3(thick, thick, length)),
		from + direction * length * 0.5
	)
	var glow := color * lerpf(1.6, 3.0, heated)
	glow.a = 0.9 * flicker
	_line_material.albedo_color = glow
	_end_material.albedo_color = glow
	_end.global_position = end
	_end.scale = Vector3.ONE * lerpf(1.0, 1.6, heated) * flicker
