class_name OstraLook
extends Node3D
## A model of Waypost Ostra's own kit (its shell, props and outside, built by the scripts in
## assets/space_station/ostra/source/): swaps the model's placeholder materials for the station's by
## their names (OstraPaint, OstraFloor, ...), and tints every object named after a room (its floor)
## by `floor_tints`. Indoor models are lit only by the rooms' lamps, like the ship's shell.

const MATERIALS: Dictionary[String, Material] = {
	"OstraPaint": preload("res://game/space_station/materials/ostra_paint.tres"),
	"OstraPaintDark": preload("res://game/space_station/materials/ostra_paint_dark.tres"),
	"OstraMetal": preload("res://game/space_station/materials/ostra_metal.tres"),
	"OstraFloor": preload("res://game/space_station/materials/ostra_floor.tres"),
	"OstraGrating": preload("res://game/space_station/materials/ostra_grating.tres"),
	"OstraHazard": preload("res://game/space_station/materials/ostra_hazard.tres"),
	"OstraRubber": preload("res://game/space_station/materials/ostra_rubber.tres"),
	"OstraFabric": preload("res://game/space_station/materials/ostra_fabric.tres"),
	"OstraWood": preload("res://game/space_station/materials/ostra_wood.tres"),
	"OstraCanvas": preload("res://game/space_station/materials/ostra_canvas.tres"),
	"OstraGlass": preload("res://game/space_station/materials/ostra_glass.tres"),
	"OstraBottle": preload("res://game/space_station/materials/ostra_bottle.tres"),
	"OstraScreen": preload("res://game/space_station/materials/ostra_screen.tres"),
	"OstraLamp": preload("res://game/space_station/materials/ostra_lamp.tres"),
	"OstraAmber": preload("res://game/space_station/materials/ostra_amber.tres"),
	"OstraRed": preload("res://game/space_station/materials/ostra_red.tres"),
	"OstraPlant": preload("res://game/space_station/materials/ostra_plant.tres"),
	"OstraOrange": preload("res://game/space_station/materials/ostra_orange.tres"),
	"OstraContainerRed": preload("res://game/space_station/materials/container_red.tres"),
	"OstraContainerBlue": preload("res://game/space_station/materials/container_blue.tres"),
	"OstraContainerOlive": preload("res://game/space_station/materials/container_olive.tres"),
}

## Lit only by the rooms' lamps (`RenderLayers.INTERIOR`); off for the outside (sunlit).
@export var interior: bool = true
## The floors' tints by room name (around 1: a hue, not a brightness).
@export var floor_tints: Dictionary[StringName, Color] = {}


func _ready() -> void:
	if interior:
		RenderLayers.put(self, RenderLayers.INTERIOR)
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		for i: int in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(i)
			if material and MATERIALS.has(material.resource_name):
				mesh_instance.set_surface_override_material(i, MATERIALS[material.resource_name])
		var tint: Variant = floor_tints.get(StringName(mesh_instance.name))
		if tint != null:
			mesh_instance.set_instance_shader_parameter(&"room_tint", tint as Color)
