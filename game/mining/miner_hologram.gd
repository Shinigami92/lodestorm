class_name MinerHologram
extends RefCounted
## A miner's look while it's placed or picked up (see `Miner.built`): projected onto its node as a
## hologram that is the real miner up to the build line (`show`). Below the line every opaque part
## shows its own material (`miner_build.gdshader`, made from its StandardMaterial3D), above it the
## hologram (`miner_hologram.gdshader`, as its overlay), with a bright line where they meet; the
## other parts (the glass) show only as the hologram until it's done. The line is a per-instance
## shader parameter, so all miners share the materials. `hide` puts the parts' own materials back.

const BUILD_SHADER: Shader = preload("res://game/mining/miner_build.gdshader")
const HOLOGRAM_SHADER: Shader = preload("res://game/mining/miner_hologram.gdshader")

## The hologram overlay, and the build materials by the material they're made from: shared.
static var _hologram: ShaderMaterial
static var _built: Dictionary[Material, ShaderMaterial] = {}

## Whether the hologram shows.
var shown: bool = false

var _meshes: Array[MeshInstance3D] = []
## The parts' own overlays and overrides, put back by `hide`.
var _overlays: Array[Material] = []
var _overrides: Array[Material] = []


## Shows `meshes` (a miner's parts).
func _init(meshes: Array[MeshInstance3D]) -> void:
	_meshes = meshes


## Shows the hologram, the real miner up to `line` (world Y); `energy` (0–1) dims the hologram.
func show(line: float, energy: float = 1.0) -> void:
	if not shown:
		_apply()
	for mesh: MeshInstance3D in _meshes:
		mesh.set_instance_shader_parameter(&"build_line", line)
		mesh.set_instance_shader_parameter(&"energy", energy)


## Puts the parts' own materials back.
func hide() -> void:
	if not shown:
		return
	shown = false
	for index: int in _meshes.size():
		var mesh: MeshInstance3D = _meshes[index]
		if not is_instance_valid(mesh):
			continue
		mesh.material_overlay = _overlays[index]
		mesh.material_override = _overrides[index]
		for surface: int in mesh.get_surface_override_material_count():
			mesh.set_surface_override_material(surface, null)


func _apply() -> void:
	shown = true
	_overlays.clear()
	_overrides.clear()
	for mesh: MeshInstance3D in _meshes:
		_overlays.append(mesh.material_overlay)
		_overrides.append(mesh.material_override)
		mesh.material_overlay = _hologram_material()
		if mesh.material_override:
			# Its own look (the glass) isn't rebuilt: only the hologram shows.
			mesh.material_override = _hologram_material()
			continue
		for surface: int in mesh.get_surface_override_material_count():
			var built: ShaderMaterial = _built_material(mesh.mesh.surface_get_material(surface))
			mesh.set_surface_override_material(surface, built if built else _hologram_material())


static func _hologram_material() -> ShaderMaterial:
	if not _hologram:
		_hologram = ShaderMaterial.new()
		_hologram.shader = HOLOGRAM_SHADER
	return _hologram


## The build material made from `source` (an opaque StandardMaterial3D), or null for any other.
static func _built_material(source: Material) -> ShaderMaterial:
	var base := source as BaseMaterial3D
	if not base or base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return null
	if _built.has(base):
		return _built[base]
	var built := ShaderMaterial.new()
	built.shader = BUILD_SHADER
	built.set_shader_parameter(&"albedo", base.albedo_color)
	built.set_shader_parameter(&"albedo_texture", base.albedo_texture)
	built.set_shader_parameter(&"roughness", base.roughness)
	built.set_shader_parameter(&"roughness_texture", base.roughness_texture)
	built.set_shader_parameter(&"roughness_channel", _channel(base.roughness_texture_channel))
	built.set_shader_parameter(&"metallic", base.metallic)
	built.set_shader_parameter(&"metallic_texture", base.metallic_texture)
	built.set_shader_parameter(&"metallic_channel", _channel(base.metallic_texture_channel))
	built.set_shader_parameter(&"specular", base.metallic_specular)
	built.set_shader_parameter(&"use_normal_map", base.normal_enabled)
	built.set_shader_parameter(&"normal_texture", base.normal_texture)
	built.set_shader_parameter(&"normal_scale", base.normal_scale)
	built.set_shader_parameter(&"use_ao", base.ao_enabled)
	built.set_shader_parameter(&"ao_texture", base.ao_texture)
	built.set_shader_parameter(&"ao_channel", _channel(base.ao_texture_channel))
	built.set_shader_parameter(&"ao_light_affect", base.ao_light_affect)
	if base.emission_enabled:
		built.set_shader_parameter(&"emission", base.emission)
		built.set_shader_parameter(&"emission_energy", base.emission_energy_multiplier)
	_built[base] = built
	return built


## The texture channel as the vector the shader reads it with.
static func _channel(channel: BaseMaterial3D.TextureChannel) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0.0, 1.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0.0, 0.0, 1.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0.0, 0.0, 0.0, 1.0)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
			return Vector4(1.0, 1.0, 1.0, 0.0) / 3.0
	return Vector4(1.0, 0.0, 0.0, 0.0)
