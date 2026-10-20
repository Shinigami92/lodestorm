class_name HeatGlow
extends MeshInstance3D
## A part of a heat-fed weapon's model that glows with its heat (a barrel, cooling fins): dark when
## cold, red to orange-white as it heats up, flickering while it vents (see `HeatAmmo`). Its
## material is its own copy of the mesh's, so it works on a station's rack too (cold there).

## The glow at full heat, and how strongly it glows.
@export var color := Color(1.0, 0.32, 0.06)
@export var hot_color := Color(1.0, 0.75, 0.4)
@export var energy: float = 4.0

var _material: StandardMaterial3D

@onready var _weapon: Weapon = owner as Weapon


func _ready() -> void:
	var base: StandardMaterial3D = (
		mesh.surface_get_material(0) as StandardMaterial3D if mesh else null
	)
	_material = base.duplicate() as StandardMaterial3D if base else StandardMaterial3D.new()
	_material.emission_enabled = true
	_material.emission = Color.BLACK
	OccludedSilhouette.write_stencil(_material)
	material_override = _material


func _process(_delta: float) -> void:
	var ammo: HeatAmmo = _weapon.ammo as HeatAmmo if _weapon else null
	var heat: float = ammo.heat if ammo else 0.0
	var venting: bool = ammo != null and ammo.venting
	var glow: float = heat * heat * energy
	if venting:
		glow *= randf_range(0.6, 1.0)
	_material.emission = color.lerp(hot_color, heat * heat) * glow
