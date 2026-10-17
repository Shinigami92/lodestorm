class_name MkPips
extends Node3D
## Shows an MK level in the world (on a weapon, on the suit): small pips in rows along X, one per
## MK level of the upgrade, centered on this node. Reached levels glow, the others stay dark, so
## the pips also show how far it can go. More than `row_levels` levels take a second row (along Z,
## filled after the first), and a row keeps the length of `fit_levels` pips, its pips a bit
## narrower when it holds more. Greybox until the art pass.

const COLOR_LIT := Color(0.85, 0.92, 1.0)
const COLOR_DARK := Color(0.06, 0.065, 0.07)

static var _lit_materials: Dictionary[Color, StandardMaterial3D] = {}
static var _dark_material: StandardMaterial3D

## Size of one pip in m.
@export var pip_size := Vector3(0.036, 0.016, 0.036)
## Distance between the pips' centers in m.
@export var spacing: float = 0.05
## How many pips fit in a row at `pip_size` and `spacing`; a longer row squeezes its pips into
## that length.
@export var fit_levels: int = 3
## The most pips in one row; more levels take more rows (MK8: two rows of four).
@export var row_levels: int = 4
## Glow of the reached levels; a part of a weapon may use its own (e.g. the magazine's in the
## ammo color).
@export var lit_color: Color = COLOR_LIT

## The MK level shown and the highest one.
var mk: int = 0
var max_mk: int = 0


## Shows MK `new_mk` of `new_max_mk` levels. Works before the node enters the tree, so a holder
## can mark the pips' materials together with its own.
func show_level(new_mk: int, new_max_mk: int) -> void:
	mk = new_mk
	max_mk = new_max_mk
	var rows: int = maxi(ceili(max_mk / float(row_levels)), 1)
	var per_row: int = ceili(max_mk / float(rows))
	# Squeezed: the step and the pips shrink by the same factor, so the gaps keep their share.
	var squeeze: float = 1.0
	if per_row > fit_levels:
		var length: float = (fit_levels - 1) * spacing + pip_size.x
		squeeze = length / ((per_row - 1) * spacing + pip_size.x)
	var size := Vector3(pip_size.x * squeeze, pip_size.y, pip_size.z)
	while get_child_count() < max_mk:
		var pip := MeshInstance3D.new()
		pip.mesh = BoxMesh.new()
		pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pip)
	while get_child_count() > max_mk:
		var last: Node = get_child(-1)
		remove_child(last)
		last.free()
	for i: int in max_mk:
		var pip: MeshInstance3D = get_child(i) as MeshInstance3D
		(pip.mesh as BoxMesh).size = size
		var column: float = i % per_row - (per_row - 1) * 0.5
		var row: float = floori(i / float(per_row)) - (rows - 1) * 0.5
		pip.position = Vector3(column * spacing * squeeze, 0.0, row * spacing)
		pip.material_override = lit_material(lit_color) if i < mk else dark_material()


## Number of glowing pips.
func lit_count() -> int:
	var lit: int = 0
	for pip: Node in get_children():
		if (pip as MeshInstance3D).material_override == lit_material(lit_color):
			lit += 1
	return lit


## The shared material of reached levels glowing in `color`.
static func lit_material(color: Color = COLOR_LIT) -> StandardMaterial3D:
	if color not in _lit_materials:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
		_lit_materials[color] = material
	return _lit_materials[color]


static func dark_material() -> StandardMaterial3D:
	if not _dark_material:
		_dark_material = StandardMaterial3D.new()
		_dark_material.albedo_color = COLOR_DARK
		_dark_material.metallic = 0.4
		_dark_material.roughness = 0.5
	return _dark_material
