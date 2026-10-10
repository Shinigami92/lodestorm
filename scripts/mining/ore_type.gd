class_name OreType
extends Resource
## A kind of resource that ore nodes yield and miners collect. Greybox: names and colors are
## placeholders until the art pass; each type only needs to be recognizable at a glance.

@export var display_name: String = ""
## Strong, distinct color used on the deposit, the miner gauge and later the carried resources.
@export var color: Color = Color.WHITE

var _material: StandardMaterial3D


## Shared material in the ore color, slightly glowing so it reads from the camera distance.
func get_material() -> StandardMaterial3D:
	if not _material:
		_material = StandardMaterial3D.new()
		_material.albedo_color = color
		_material.emission_enabled = true
		_material.emission = color
		_material.emission_energy_multiplier = 0.4
	return _material
