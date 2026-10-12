class_name MkPips
extends Node3D
## Shows an MK level in the world (on a weapon, on the suit): a row of small pips along X, one per
## MK level of the upgrade, centered on this node. Reached levels glow, the others stay dark, so
## the row also shows how far it can go. Greybox until the art pass.

const COLOR_LIT := Color(0.85, 0.92, 1.0)
const COLOR_DARK := Color(0.06, 0.065, 0.07)

static var _lit_material: StandardMaterial3D
static var _dark_material: StandardMaterial3D

## Size of one pip in m.
@export var pip_size := Vector3(0.036, 0.016, 0.036)
## Distance between the pips' centers in m.
@export var spacing: float = 0.05

## The MK level shown and the highest one.
var mk: int = 0
var max_mk: int = 0


## Shows MK `new_mk` of `new_max_mk` levels. Works before the node enters the tree, so a holder
## can mark the pips' materials together with its own.
func show_level(new_mk: int, new_max_mk: int) -> void:
	mk = new_mk
	max_mk = new_max_mk
	while get_child_count() < max_mk:
		var pip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = pip_size
		pip.mesh = box
		pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pip)
	while get_child_count() > max_mk:
		var last: Node = get_child(-1)
		remove_child(last)
		last.free()
	for i: int in max_mk:
		var pip: MeshInstance3D = get_child(i) as MeshInstance3D
		pip.position = Vector3((i - (max_mk - 1) * 0.5) * spacing, 0.0, 0.0)
		pip.material_override = lit_material() if i < mk else dark_material()


## Number of glowing pips.
func lit_count() -> int:
	var lit: int = 0
	for pip: Node in get_children():
		if (pip as MeshInstance3D).material_override == lit_material():
			lit += 1
	return lit


static func lit_material() -> StandardMaterial3D:
	if not _lit_material:
		_lit_material = StandardMaterial3D.new()
		_lit_material.albedo_color = COLOR_LIT
		_lit_material.emission_enabled = true
		_lit_material.emission = COLOR_LIT
		_lit_material.emission_energy_multiplier = 2.0
	return _lit_material


static func dark_material() -> StandardMaterial3D:
	if not _dark_material:
		_dark_material = StandardMaterial3D.new()
		_dark_material.albedo_color = COLOR_DARK
		_dark_material.metallic = 0.4
		_dark_material.roughness = 0.5
	return _dark_material
