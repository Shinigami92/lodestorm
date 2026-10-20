class_name WindingPart
extends MeshInstance3D
## A part of a weapon's model following how far its trigger has wound up (`Weapon.wind`: Clout's
## pistons drawing back and its core glowing as its punch charges): it moves by `travel` (in its
## parent's axes) and, with `energy` above 0, glows from dark to `color` and white at the end. Its
## material is its own copy of the mesh's, so it works on a station's rack too (still there).

## How far it moves when fully wound up (m).
@export var travel := Vector3.ZERO
## The glow while it winds up, and when full; how strongly it glows (0: it doesn't).
@export var color := Color(1.0, 0.62, 0.2)
@export var full_color := Color(1.0, 0.95, 0.85)
@export var energy: float = 0.0

var _material: StandardMaterial3D
var _rest := Vector3.ZERO

@onready var _weapon: Weapon = owner as Weapon


func _ready() -> void:
	_rest = position
	if energy <= 0.0:
		return
	var base: StandardMaterial3D = (
		mesh.surface_get_material(0) as StandardMaterial3D if mesh else null
	)
	_material = base.duplicate() as StandardMaterial3D if base else StandardMaterial3D.new()
	_material.emission_enabled = true
	OccludedSilhouette.write_stencil(_material)
	material_override = _material


func _process(_delta: float) -> void:
	var wind: float = _weapon.wind if _weapon else 0.0
	position = _rest + travel * wind
	if _material:
		var glow: Color = full_color if wind >= 1.0 else color
		_material.emission = glow * energy * (0.35 + 0.65 * wind)
