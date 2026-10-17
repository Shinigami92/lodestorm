class_name OccludedSilhouette
extends RefCounted
## Shows bodies hidden behind cliffs, plants or walls as see-through silhouettes in a color
## (`assets/shaders/occluded_silhouette.gdshader`), so what matters stays readable from the
## isometric camera: players, aliens, miners, ore, unopened crates. Only a depth and stencil
## test, so it works from any camera, VR's too. A body's meshes mark where they're visible in the
## stencil buffer (`mark_visible`), so its silhouette only shows where something else hides it.

const SHADER: Shader = preload("res://assets/shaders/occluded_silhouette.gdshader")
## Stencil value bodies write where they're visible (the silhouette skips those pixels).
const STENCIL_VISIBLE: int = 1
const PLAYER_COLOR := Color(0.95, 0.55, 0.15, 0.7)
const ALIEN_COLOR := Color(0.95, 0.15, 0.1, 0.6)
const MINER_COLOR := Color(0.6, 0.85, 1.0, 0.55)
const CRATE_COLOR := Color(1.0, 0.72, 0.28, 0.5)
## Ore shows fainter than the rest, in its own color.
const ORE_ALPHA: float = 0.5


## A silhouette material in `color` (its alpha: how strong) to put first in a mesh's overlay
## chain; `then` follows it (e.g. the rim light).
static func overlay(color: Color, then: Material = null) -> ShaderMaterial:
	var silhouette := ShaderMaterial.new()
	silhouette.shader = SHADER
	silhouette.render_priority = 1
	silhouette.set_shader_parameter(&"color", color)
	silhouette.next_pass = then
	return silhouette


## Lets the meshes under `root` mark where they're visible in the stencil buffer. Marks their
## materials in place (the imported ones are shared by all bodies of a kind, which is fine).
static func mark_visible(root: Node) -> void:
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node: Node in meshes:
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.material_override:
			write_stencil(mesh.material_override as BaseMaterial3D)
			continue
		if not mesh.mesh:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			write_stencil(mesh.mesh.surface_get_material(surface) as BaseMaterial3D)


## Makes `material` mark where it's visible (see `mark_visible`), e.g. for meshes built later.
static func write_stencil(material: BaseMaterial3D) -> void:
	if not material:
		return
	material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	material.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	material.stencil_reference = STENCIL_VISIBLE
