class_name SparePouches
extends Node3D
## The spare magazines of the equipped ranged weapon, shown on the suit: a row of cells along X
## (on top of the backpack), one per spare magazine a run starts with. Full ones glow in the
## weapon's ammo color, a partly used one (single rounds) glows dimmer, used ones stay dark.
## Greybox until the art pass.

const DARK := Color(0.05, 0.05, 0.055)

## Size of one pouch in m.
@export var pouch_size := Vector3(0.07, 0.035, 0.09)
## Distance between the pouches' centers in m.
@export var spacing: float = 0.09
## How wide the row gets at most (m): more pouches (spare magazine skill) get narrower.
@export var max_width: float = 0.3
## How strongly full pouches glow.
@export var energy: float = 2.5

var _materials: Array[StandardMaterial3D] = []


## Shows `magazines` spare magazines (a fraction: a partly used one) of `slots` in `color`.
## Works before the node enters the tree.
func show_spares(magazines: float, slots: int, color: Color) -> void:
	if _materials.size() != slots:
		_build(slots)
	for i: int in slots:
		var fill: float = clampf(magazines - i, 0.0, 1.0)
		var material: StandardMaterial3D = _materials[i]
		material.albedo_color = DARK.lerp(color * 0.3, fill)
		material.emission = color * energy * fill * fill


## Number of pouches that glow (full or partly).
func lit_count() -> int:
	var lit: int = 0
	for material: StandardMaterial3D in _materials:
		if material.emission.v > 0.0:
			lit += 1
	return lit


func _build(slots: int) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_materials.clear()
	var step: float = minf(spacing, max_width / maxi(slots, 1))
	var size := Vector3(pouch_size.x * step / spacing, pouch_size.y, pouch_size.z)
	for i: int in slots:
		var material := StandardMaterial3D.new()
		material.emission_enabled = true
		material.roughness = 0.6
		OccludedSilhouette.write_stencil(material)
		var box := BoxMesh.new()
		box.size = size
		var pouch := MeshInstance3D.new()
		pouch.mesh = box
		pouch.material_override = material
		pouch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pouch.position = Vector3((i - (slots - 1) * 0.5) * step, 0.0, 0.0)
		add_child(pouch)
		_materials.append(material)
