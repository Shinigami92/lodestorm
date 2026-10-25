class_name ShipShell
extends Node3D
## A part of the ship's shell made from the modular kit (assets/ship/shell/<group>.glb, built by
## assets/ship/source/ship_shell_build.py and placed under its cut-away group's node by
## hull_build.py): swaps the model's placeholder materials for the shell's by their names, and gives
## every object named after a room (its floor and accents) that room's RoomLook.

const LOOKS: RoomLooks = preload("res://game/ship/room_looks.tres")
const MATERIALS: Dictionary[String, Material] = {
	"ShellPaint": preload("res://game/ship/shell/shell_paint.tres"),
	"ShellDark": preload("res://game/ship/shell/shell_dark.tres"),
	"ShellPlate": preload("res://game/ship/shell/shell_plate.tres"),
	"ShellGrating": preload("res://game/ship/shell/shell_grating.tres"),
	"ShellHazard": preload("res://game/ship/shell/shell_hazard.tres"),
	"ShellMarking": preload("res://game/ship/shell/shell_marking.tres"),
	"ShellAccent": preload("res://game/ship/shell/shell_accent.tres"),
	"ShellLamp": preload("res://game/ship/shell/shell_lamp.tres"),
}


func _ready() -> void:
	RenderLayers.put(self, RenderLayers.INTERIOR)
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh: Mesh = mesh_instance.mesh
		for i: int in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(i)
			if material and MATERIALS.has(material.resource_name):
				mesh_instance.set_surface_override_material(i, MATERIALS[material.resource_name])
		# A room's floor is named after it, its accents "<room>Accent": apart, since instance shader
		# parameters of different names share slots within one object.
		var room: String = mesh_instance.name
		var is_accent: bool = room.ends_with("Accent")
		var look: RoomLook = LOOKS.get_look(StringName(room.trim_suffix("Accent")))
		if look and is_accent:
			mesh_instance.set_instance_shader_parameter(&"accent", look.accent_color)
		elif look:
			mesh_instance.set_instance_shader_parameter(&"room_tint", look.floor_tint)
