class_name SettledCover
extends RefCounted
## The biome's loose cover (snow, salt, ash, dust) on a map part's props: an overlay
## (`assets/shaders/settled_cover.gdshader`) with the biome's ground texture where faces point up
## and around the props' foot, so a part looks like it has stood there a long time. Every
## `KitMesh` with `cover` gets it; one material per biome. How much settles is the biome's
## `part_cover`.

const SHADER: Shader = preload("res://assets/shaders/settled_cover.gdshader")

static var _materials: Dictionary[LocationBiome, ShaderMaterial] = {}


## The cover material of `biome`, or null if nothing settles there.
static func material(biome: LocationBiome) -> ShaderMaterial:
	if not biome or biome.part_cover <= 0.0:
		return null
	if _materials.has(biome):
		return _materials[biome]
	var ground := biome.ground_material as ShaderMaterial
	if not ground:
		return null
	var cover := ShaderMaterial.new()
	cover.shader = SHADER
	cover.set_shader_parameter(&"cover_albedo", ground.get_shader_parameter(&"ground_albedo"))
	cover.set_shader_parameter(&"cover_nra", ground.get_shader_parameter(&"ground_nra"))
	var tile: Variant = ground.get_shader_parameter(&"ground_tile")
	if tile is float:
		cover.set_shader_parameter(&"cover_tile", tile)
	cover.set_shader_parameter(&"cover_tint", biome.part_cover_tint)
	cover.set_shader_parameter(&"amount", biome.part_cover)
	_materials[biome] = cover
	return cover


## Gives every `KitMesh` with `cover` under `part` the cover of `biome`.
static func apply(part: Node, biome: LocationBiome) -> void:
	var cover: ShaderMaterial = material(biome)
	if not cover:
		return
	for node: Node in part.find_children("*", "KitMesh", true, false):
		var piece := node as KitMesh
		if piece.cover:
			piece.material_overlay = cover
