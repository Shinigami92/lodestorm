class_name ShellStrip
extends AmmoGauge
## An ammo gauge of glowing shells in a row along -Z (e.g. on the shotgun's side), one per round,
## spread over `length`. Greybox until the art pass.

## Size of the strip in m: X and Y of each shell, Z the length of the row.
@export var size := Vector3(0.104, 0.025, 0.2)
## Gap between the shells in m.
@export var gap: float = 0.004

var _materials: Array[StandardMaterial3D] = []


func build(capacity: int) -> void:
	if _materials.size() == capacity:
		return
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_materials.clear()
	var pitch: float = size.z / capacity
	for i: int in capacity:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.05, 0.045, 0.04)
		material.emission_enabled = true
		OccludedSilhouette.write_stencil(material)
		var box := BoxMesh.new()
		box.size = Vector3(size.x, size.y, pitch - gap)
		var shell := MeshInstance3D.new()
		shell.mesh = box
		shell.material_override = material
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The first round sits at the front.
		shell.position.z = -size.z * 0.5 + pitch * (i + 0.5)
		add_child(shell)
		_materials.append(material)


func show_state(weapon: RangedWeapon) -> void:
	var glow: Array[Color] = segment_glow(weapon, _materials.size())
	for i: int in _materials.size():
		_materials[i].emission = glow[i]
