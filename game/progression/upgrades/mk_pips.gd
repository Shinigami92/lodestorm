class_name MkPips
extends Node3D
## Shows an MK level in the world (on a weapon, on the suit): small pips in rows along X, one per
## MK level of the upgrade, centered on this node. Reached levels glow, the others stay dark, so
## the pips also show how far it can go. More than `row_levels` levels take a second row (along Z,
## filled after the first), and a row keeps the length of `fit_levels` pips, its pips a bit
## narrower when it holds more. The pip of a level under way (see `Upgrades.jobs`) breathes dimly
## and flashes once when it's done. Greybox until the art pass.

const COLOR_LIT := Color(0.85, 0.92, 1.0)
const COLOR_DARK := Color(0.06, 0.065, 0.07)
## How long a level done flashes, in s.
const FLASH_TIME: float = 0.4
const BREATHING_SHADER: String = """
shader_type spatial;

uniform vec3 color : source_color;
uniform vec3 dark : source_color;

void fragment() {
	float breath = 0.5 + 0.5 * sin(TIME * 2.5);
	ALBEDO = mix(dark, color, 0.2 + 0.2 * breath);
	EMISSION = color * (0.1 + 0.6 * breath);
	METALLIC = 0.4;
	ROUGHNESS = 0.5;
}
"""

static var _lit_materials: Dictionary[Color, StandardMaterial3D] = {}
static var _breathing_materials: Dictionary[Color, ShaderMaterial] = {}
static var _flash_materials: Dictionary[Color, StandardMaterial3D] = {}
static var _dark_material: StandardMaterial3D
static var _breathing_shader: Shader

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
## Whether the level after `mk` is under way.
var under_way: bool = false

var _flashing: int = -1


## Shows MK `new_mk` of `new_max_mk` levels, the next one under way when `new_under_way`. Works
## before the node enters the tree, so a holder can mark the pips' materials together with its
## own. The level that was under way flashes once when it's shown reached.
func show_level(new_mk: int, new_max_mk: int, new_under_way: bool = false) -> void:
	if under_way and new_mk == mk + 1 and new_max_mk == max_mk and is_inside_tree():
		_flash(mk)
	mk = new_mk
	max_mk = new_max_mk
	under_way = new_under_way and mk < max_mk
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
		pip.material_override = _material(i)


## The material of the pip for level `index` + 1.
func _material(index: int) -> Material:
	if index == _flashing:
		return flash_material(lit_color)
	if index < mk:
		return lit_material(lit_color)
	if under_way and index == mk:
		return breathing_material(lit_color)
	return dark_material()


func _flash(index: int) -> void:
	_flashing = index
	get_tree().create_timer(FLASH_TIME).timeout.connect(_end_flash.bind(index))


func _end_flash(index: int) -> void:
	if _flashing != index:
		return
	_flashing = -1
	if index < get_child_count():
		(get_child(index) as MeshInstance3D).material_override = _material(index)


## Number of glowing pips (a flashing one too, not one breathing).
func lit_count() -> int:
	var lit: int = 0
	for pip: Node in get_children():
		var material: Material = (pip as MeshInstance3D).material_override
		if material in [lit_material(lit_color), flash_material(lit_color)]:
			lit += 1
	return lit


## Whether a pip breathes for a level under way.
func is_breathing() -> bool:
	for pip: Node in get_children():
		if (pip as MeshInstance3D).material_override == breathing_material(lit_color):
			return true
	return false


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


## The shared material of a level under way breathing dimly in `color`.
static func breathing_material(color: Color = COLOR_LIT) -> ShaderMaterial:
	if color not in _breathing_materials:
		if not _breathing_shader:
			_breathing_shader = Shader.new()
			_breathing_shader.code = BREATHING_SHADER
		var material := ShaderMaterial.new()
		material.shader = _breathing_shader
		material.set_shader_parameter(&"color", color)
		material.set_shader_parameter(&"dark", COLOR_DARK)
		_breathing_materials[color] = material
	return _breathing_materials[color]


## The shared material of a level just done, flashing bright in `color`.
static func flash_material(color: Color = COLOR_LIT) -> StandardMaterial3D:
	if color not in _flash_materials:
		var material: StandardMaterial3D = lit_material(color).duplicate()
		material.emission_energy_multiplier = 8.0
		_flash_materials[color] = material
	return _flash_materials[color]


static func dark_material() -> StandardMaterial3D:
	if not _dark_material:
		_dark_material = StandardMaterial3D.new()
		_dark_material.albedo_color = COLOR_DARK
		_dark_material.metallic = 0.4
		_dark_material.roughness = 0.5
	return _dark_material
