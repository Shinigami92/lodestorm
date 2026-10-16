class_name DashStrip
extends Node3D
## The dash's cooldown, shown on the suit: a short light strip along X (across the back of the
## backpack) that fills up again from the left after a dash and glows brighter once the dash is
## ready. Warm white, apart from the ammo colors of the spare magazine cells. Hidden without the
## dash skill. Greybox until the art pass.

const COLOR := Color(1.0, 0.93, 0.8)
const DARK := Color(0.05, 0.05, 0.055)

## Size of the strip in m.
@export var strip_size := Vector3(0.2, 0.03, 0.012)
## How strongly it glows when ready, and while it fills.
@export var ready_energy: float = 3.0
@export var filling_energy: float = 0.8

## How full it is (1: the dash is ready).
var fill: float = 1.0

var _back := MeshInstance3D.new()
var _fill := MeshInstance3D.new()
var _fill_material := StandardMaterial3D.new()


func _init() -> void:
	var back_mesh := BoxMesh.new()
	back_mesh.size = strip_size
	var back_material := StandardMaterial3D.new()
	back_material.albedo_color = DARK
	back_mesh.material = back_material
	_back.mesh = back_mesh
	add_child(_back)
	var fill_mesh := BoxMesh.new()
	# A little bigger, so it covers the dark strip where it's filled.
	fill_mesh.size = strip_size + Vector3(0.0, 0.004, 0.004)
	_fill_material.emission_enabled = true
	fill_mesh.material = _fill_material
	_fill.mesh = fill_mesh
	add_child(_fill)
	for mesh: MeshInstance3D in [_back, _fill]:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	show_fill(1.0)


## Shows the cooldown: `ratio` 0 right after a dash, 1 when it's ready. Works before the node
## enters the tree.
func show_fill(ratio: float) -> void:
	fill = clampf(ratio, 0.0, 1.0)
	_fill.visible = fill > 0.0
	_fill.scale = Vector3(maxf(fill, 0.001), 1.0, 1.0)
	_fill.position = Vector3(-strip_size.x * 0.5 * (1.0 - fill), 0.0, 0.0)
	var energy: float = ready_energy if fill >= 1.0 else filling_energy
	_fill_material.albedo_color = COLOR * 0.4
	_fill_material.emission = COLOR * energy
