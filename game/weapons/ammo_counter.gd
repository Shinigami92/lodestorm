class_name AmmoCounter
extends AmmoGauge
## An ammo gauge on a modeled weapon: the glowing segments of its mesh `mesh_name` (one UV.x value
## per segment, `(i + 0.5) / segments` from the rear to the front, e.g. Harl's counter),
## lit through a texture with one pixel per segment.

## Name of the segment mesh in the weapon's model.
@export var mesh_name: String = "AmmoCounter"
@export var segments: int = 6

var _image: Image
var _texture: ImageTexture
var _material: StandardMaterial3D


func build(_capacity: int) -> void:
	if _material:
		return
	_image = Image.create_empty(segments, 1, false, Image.FORMAT_RGBAH)
	_texture = ImageTexture.create_from_image(_image)
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.03, 0.035, 0.04)
	_material.roughness = 0.4
	_material.emission_enabled = true
	_material.emission = Color.WHITE
	_material.emission_texture = _texture
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var mesh := get_parent().find_child(mesh_name) as MeshInstance3D
	if mesh:
		mesh.material_override = _material


func show_state(ammo: WeaponAmmo) -> void:
	if not _image:
		return
	var glow: Array[Color] = segment_glow(ammo, segments)
	for i: int in segments:
		_image.set_pixel(i, 0, glow[i])
	_texture.update(_image)
