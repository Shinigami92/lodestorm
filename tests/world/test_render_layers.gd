extends GutTest
## Decals (the aim reticle, a charge's lane) only reach `RenderLayers.WORLD`, so only surfaces may
## sit there: text, sprites, particles, holograms and effects (shader or see-through materials) go
## on another layer, or the reticle paints itself onto them. Lit, opaque meshes, glowing light
## strips and the ship's windows (upright, the reticle fades out on them) stay on WORLD.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
## Shaders of surfaces: decals land on them.
const SURFACE_SHADERS: Array[String] = ["terrain.gdshader", "ore_crystal.gdshader"]


func test_only_surfaces_catch_decals() -> void:
	var map: Node3D = TEST_MAP.instantiate()
	add_child_autofree(map)
	await wait_physics_frames(3)
	ScreamWave.spawn(map, Vector3.ZERO, 4.0)
	DustPuff.spawn(map, Vector3.ZERO)
	HitSpray.spawn(map, Vector3.ZERO, Vector3.FORWARD, false)
	await wait_process_frames(2)
	var wrong: Array[String] = []
	for node: Node in map.find_children("*", "GeometryInstance3D", true, false):
		var visual := node as GeometryInstance3D
		if visual.layers & RenderLayers.WORLD and _is_effect(visual):
			wrong.append(str(map.get_path_to(visual)))
	assert_eq(wrong.size(), 0, "on RenderLayers.WORLD:\n" + "\n".join(wrong))


## Whether `visual` isn't a surface: text, a sprite, particles, a shader or see-through material.
func _is_effect(visual: GeometryInstance3D) -> bool:
	if visual is Label3D or visual is SpriteBase3D:
		return true
	if visual is GPUParticles3D or visual is CPUParticles3D:
		return true
	if visual.is_in_group(CutAway.HIDE_GROUP):
		return false
	for material: Material in _materials(visual):
		var shader := material as ShaderMaterial
		if (
			shader
			and shader.shader
			and shader.shader.resource_path.get_file() not in SURFACE_SHADERS
		):
			return true
		var base := material as BaseMaterial3D
		if base and base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
	return false


func _materials(visual: GeometryInstance3D) -> Array[Material]:
	var materials: Array[Material] = []
	if visual.material_override:
		materials.append(visual.material_override)
	var mesh_instance := visual as MeshInstance3D
	if mesh_instance and mesh_instance.mesh:
		for i: int in mesh_instance.mesh.get_surface_count():
			if mesh_instance.get_active_material(i):
				materials.append(mesh_instance.get_active_material(i))
	var multi := visual as MultiMeshInstance3D
	if multi and multi.multimesh and multi.multimesh.mesh:
		for i: int in multi.multimesh.mesh.get_surface_count():
			if multi.multimesh.mesh.surface_get_material(i):
				materials.append(multi.multimesh.mesh.surface_get_material(i))
	return materials
