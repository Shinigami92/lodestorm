class_name OreType
extends Resource
## A kind of resource that ore nodes yield and miners collect. Greybox: names and colors are
## placeholders until the art pass; each type only needs to be recognizable at a glance.

@export var display_name: String = ""
## Strong, distinct color used on the deposit, the miner gauge and later the carried resources.
@export var color: Color = Color.WHITE
## Model kit (.glb) with the look of this type's ore nodes; the greybox stays without one.
@export var model: PackedScene
## Names of the variants in `model`: each is a node with a `Base*` mesh (the rock the crystals
## grow out of) and `Crystal*` meshes (drawn in the ore's glowing material).
@export var variants: Array[StringName] = []

var _material: StandardMaterial3D


## Shared material in the ore color. It glows (and blooms) strongly: in the muted, dark world
## the ore is one of the few saturated, bright things, so it reads from the camera distance.
func get_material() -> StandardMaterial3D:
	if not _material:
		_material = StandardMaterial3D.new()
		_material.albedo_color = color
		_material.roughness = 0.2
		_material.emission_enabled = true
		_material.emission = color
		_material.emission_energy_multiplier = 2.5
	return _material
